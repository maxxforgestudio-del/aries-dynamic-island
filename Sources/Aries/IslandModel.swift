import AppKit
import SwiftUI
import Combine

struct Toast: Equatable, Hashable {
    var id = UUID()
    let icon: String
    let tint: Color
    let title: String
    let detail: String
    var detailIcon: String? = nil
    /// Shown first, then swapped to `icon` (e.g. lock → lock.open).
    var fromIcon: String? = nil
    /// When set, the right wing shows a little level bar (volume HUD).
    var level: Double? = nil
    /// Album art for "now playing" announcements.
    var image: NSImage? = nil
}

enum CompactState: Hashable {
    case idle
    case indicators
    case timer
    case call
    case music
    case toast(Toast)
}

enum IslandTab: String, CaseIterable, Identifiable {
    case call, home, music, notes, shelf, timer, clipboard, mirror
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .call: return "phone.fill"
        case .home: return "house.fill"
        case .music: return "music.note"
        case .notes: return "note.text"
        case .shelf: return "tray.full.fill"
        case .timer: return "timer"
        case .clipboard: return "doc.on.clipboard.fill"
        case .mirror: return "person.crop.square.fill"
        }
    }
    var title: String { rawValue.capitalized }
}

enum MusicPanel: String { case player, queue, devices, search }

final class IslandModel: ObservableObject {
    let music: MusicController
    let system: SystemMonitor
    let shelf = ShelfStore()
    let timer = TimerModel()
    let calendar = CalendarModel()
    let notes = NotesStore()
    let clipboard = ClipboardStore()
    let weather = WeatherModel()
    let calls = CallMonitor()
    let mirror = MirrorCamera()
    private let audio = AudioMonitor()

    @Published private(set) var notchSize = CGSize(width: 185, height: 32)
    @Published private(set) var isExpanded = false
    @Published private(set) var isHovering = false
    @Published private(set) var toast: Toast?
    @Published private(set) var musicVisible = false
    @Published var tab: IslandTab = .home
    @Published var musicPanel: MusicPanel = .player
    /// True while a text field in the island is being edited (keeps it open).
    @Published var isEditing = false
    /// Bumped to ask the Notes field to take keyboard focus.
    @Published var focusNotes = 0
    @Published var dropTargeted = false {
        didSet { if dropTargeted && !oldValue { expand(to: .shelf) } }
    }
    /// Bumped to fire a confetti burst.
    @Published private(set) var celebration = 0

    var onLayoutChange: (() -> Void)?

    private var hovering = false
    private var expandWork: DispatchWorkItem?
    private var collapseWork: DispatchWorkItem?
    private var toastWork: DispatchWorkItem?
    private var lingerWork: DispatchWorkItem?
    private var bag = Set<AnyCancellable>()

    init(music: MusicController, system: SystemMonitor) {
        self.music = music
        self.system = system

        for publisher in [system.objectWillChange.eraseToAnyPublisher(),
                          timer.objectWillChange.eraseToAnyPublisher(),
                          shelf.objectWillChange.eraseToAnyPublisher(),
                          calendar.objectWillChange.eraseToAnyPublisher(),
                          calls.objectWillChange.eraseToAnyPublisher()] {
            publisher.receive(on: RunLoop.main)
                .sink { [weak self] in self?.objectWillChange.send(); self?.layoutChanged() }
                .store(in: &bag)
        }

        Publishers.CombineLatest(music.$isPlaying, music.$track.map { $0?.id })
            .receive(on: RunLoop.main)
            .sink { [weak self] playing, id in self?.updateMusicVisibility(playing: playing, hasTrack: id != nil) }
            .store(in: &bag)

        system.events
            .receive(on: RunLoop.main)
            .sink { [weak self] event in self?.handle(event) }
            .store(in: &bag)

        timer.onFinish = { [weak self] in self?.timerFinished() }
        music.onConfirm = { [weak self] icon, text in self?.confirm(icon, text) }

        // Song-change announcement (like iPhone's quick bump).
        music.$track.map { $0?.id }.removeDuplicates().dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] id in
                guard id != nil else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { self?.announceSong() }
            }
            .store(in: &bag)

        // Incoming call → open the island on the call card.
        calls.$call.map { $0?.kind }.removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] kind in
                guard let self else { return }
                if kind == .incoming { self.expand(to: .call) }
                else if kind == nil, self.tab == .call {
                    self.tab = self.defaultTab()
                    if !self.hovering { self.collapse() }
                }
                self.layoutChanged()
            }
            .store(in: &bag)
        calendar.onSoon = { [weak self] e in
            self?.show(Toast(icon: e.joinURL != nil ? "video.fill" : "calendar", tint: e.color,
                             title: e.title, detail: CalendarModel.relative(e.start)), for: 5)
        }
    }

    /// Starts the live services (not used by the snapshot renderer).
    func startServices() {
        calendar.start()
        clipboard.start()
        weather.start()
        calls.start(system: system)
        audio.onVolume = { [weak self] v, muted in
            guard Prefs.bool(Prefs.volumeHUD) else { return }
            self?.showLevel(icon: AudioMonitor.volumeSymbol(v, muted: muted), title: muted ? "Muted" : "Volume",
                            level: muted ? 0 : Double(v))
        }
        audio.onDevice = { [weak self] name, symbol in
            guard Prefs.bool(Prefs.deviceToasts) else { return }
            self?.show(Toast(icon: symbol, tint: .white, title: name, detail: "Connected",
                             detailIcon: "checkmark.circle.fill"), for: 3)
        }
        audio.start()
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main
        ) { [weak self] _ in
            guard Prefs.bool(Prefs.unlockAnimation) else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                self?.show(Toast(icon: "lock.open.fill", tint: .white, title: "Welcome back",
                                 detail: Self.greeting(), fromIcon: "lock.fill"), for: 2.4)
            }
        }
    }

    static func greeting(_ d: Date = Date()) -> String {
        switch Calendar.current.component(.hour, from: d) {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Night owl"
        }
    }

    // MARK: Geometry

    func updateNotch(for screen: NSScreen) {
        let top = screen.safeAreaInsets.top
        if top > 0,
           let left = screen.auxiliaryTopLeftArea?.width,
           let right = screen.auxiliaryTopRightArea?.width {
            notchSize = CGSize(width: screen.frame.width - left - right, height: top)
        } else {
            notchSize = CGSize(width: 190, height: 32)
        }
    }

    var hasIndicators: Bool {
        (system.micActive && Prefs.bool(Prefs.showMic)) || (system.cameraActive && Prefs.bool(Prefs.showCamera))
    }

    var compact: CompactState {
        if let t = toast { return .toast(t) }
        if calls.call?.kind == .active { return .call }
        if musicVisible && music.track != nil { return .music }
        if timer.isActive { return .timer }
        if hasIndicators { return .indicators }
        return .idle
    }

    var tabs: [IslandTab] {
        var t: [IslandTab] = []
        if calls.call != nil { t.append(.call) }
        t += [.home, .music]
        if Prefs.bool(Prefs.showNotesTab) { t.append(.notes) }
        if Prefs.bool(Prefs.showShelf) { t.append(.shelf) }
        if Prefs.bool(Prefs.showTimer) { t.append(.timer) }
        if Prefs.bool(Prefs.showClipboard) { t.append(.clipboard) }
        if Prefs.bool(Prefs.showMirror) { t.append(.mirror) }
        return t
    }

    var ear: CGFloat { isExpanded ? 14 : 7 }
    var bottomRadius: CGFloat { isExpanded ? 34 : 11 }

    var bodySize: CGSize {
        let W = notchSize.width, H = notchSize.height
        if isExpanded {
            let h: CGFloat
            switch tab {
            case .music:
                if musicPanel != .player { h = 236 }
                else { h = music.track != nil ? 176 : 120 }
            case .home: h = 106
            case .notes: h = 214
            case .shelf: h = 110
            case .timer: h = timer.isActive ? 98 : 116
            case .clipboard: h = 214
            case .mirror: h = 196
            case .call: h = 92
            }
            return CGSize(width: max(W + 410, 600), height: H + h)
        }
        switch compact {
        case .idle: return CGSize(width: W, height: H)
        case .indicators: return CGSize(width: W + 2 * 34, height: H)
        case .timer: return CGSize(width: W + 2 * 46, height: H)
        case .call: return CGSize(width: W + 2 * 52, height: H)
        case .music: return CGSize(width: W + 2 * (timer.isActive ? 58 : 44), height: H)
        case .toast(let t):
            let chars = CGFloat(max(t.title.count, t.detail.count + (t.detailIcon == nil ? 0 : 3)))
            let wing = min(185, max(104, 50 + chars * 7.4))
            return CGSize(width: W + 2 * wing, height: H)
        }
    }

    var totalSize: CGSize { CGSize(width: bodySize.width + ear * 2, height: bodySize.height) }

    var layoutKey: String { "\(isExpanded)-\(compact)-\(tab)-\(musicPanel)-\(music.track != nil)-\(timer.isActive)" }

    private func layoutChanged() {
        DispatchQueue.main.async { self.onLayoutChange?() }
    }

    // MARK: Hover / expand

    func setHovering(_ inside: Bool) {
        guard inside != hovering else { return }
        hovering = inside
        if Prefs.bool(Prefs.hoverBounce) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { isHovering = inside }
        }
        if inside {
            collapseWork?.cancel()
            guard !isExpanded, Prefs.bool(Prefs.expandOnHover) else { return }
            let w = DispatchWorkItem { [weak self] in self?.expand() }
            expandWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0.0, Prefs.double(Prefs.hoverDelay)), execute: w)
        } else {
            expandWork?.cancel()
            guard isExpanded, !dropTargeted, !isEditing, calls.call?.kind != .incoming else { return }
            let w = DispatchWorkItem { [weak self] in self?.collapse() }
            collapseWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: w)
        }
    }

    func tap() {
        if !isExpanded { expand() }
    }

    private func defaultTab() -> IslandTab {
        if calls.call != nil { return .call }
        if music.track != nil && (music.isPlaying || musicVisible) { return .music }
        if timer.isActive && tabs.contains(.timer) { return .timer }
        return .home
    }

    func expand(to target: IslandTab? = nil) {
        let t = target ?? defaultTab()
        if isExpanded {
            if let target, target != tab { select(target) }
            return
        }
        tab = tabs.contains(t) ? t : .home
        if Prefs.bool(Prefs.haptics) {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.74)) { isExpanded = true }
        layoutChanged()
    }

    func select(_ t: IslandTab) {
        guard t != tab else { return }
        if Prefs.bool(Prefs.haptics) {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) { tab = t }
        layoutChanged()
    }

    func collapse() {
        guard isExpanded else { return }
        isEditing = false
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) { isExpanded = false }
        if tab == .mirror { mirror.stop() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            if self?.isExpanded == false { self?.musicPanel = .player }
        }
        onCollapse?()
        layoutChanged()
    }

    var onCollapse: (() -> Void)?

    func toggle() { isExpanded ? collapse() : expand() }

    func showMusicPanel(_ p: MusicPanel) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { musicPanel = p }
        layoutChanged()
        switch p {
        case .queue: music.loadQueue()
        case .devices: music.loadDevices()
        default: break
        }
    }

    func newNote() {
        expand(to: .notes)
        focusNotes += 1
    }

    /// Little ✓ confirmation in the notch.
    func confirm(_ icon: String, _ text: String) {
        let ok = !icon.contains("exclamation")
        if isExpanded {
            // Keep the expanded view; show a brief banner instead.
            banner = (icon, text, ok)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                if self?.banner?.1 == text { withAnimation(.spring) { self?.banner = nil } }
            }
            return
        }
        show(Toast(icon: icon, tint: ok ? (icon.contains("heart") ? .pink : .green) : .orange,
                   title: text, detail: "", detailIcon: ok ? "checkmark.circle.fill" : nil), for: 2)
    }

    @Published var banner: (String, String, Bool)?

    private func announceSong() {
        guard Prefs.bool(Prefs.announceSongs), !isExpanded, toast == nil, music.isPlaying,
              let t = music.track else { return }
        show(Toast(icon: "music.note", tint: music.accent, title: t.title, detail: t.artist,
                   image: music.artwork), for: 2.6)
    }

    // MARK: Music visibility (stay a bit after pausing, like iPhone)

    private func updateMusicVisibility(playing: Bool, hasTrack: Bool) {
        lingerWork?.cancel()
        let target: Bool
        if !hasTrack { target = false }
        else if playing { target = true }
        else {
            target = musicVisible
            let w = DispatchWorkItem { [weak self] in
                guard let self, !self.music.isPlaying else { return }
                self.setMusicVisible(false)
            }
            lingerWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + max(2, Prefs.double(Prefs.pausedLinger)), execute: w)
        }
        setMusicVisible(target)
    }

    private func setMusicVisible(_ v: Bool) {
        guard v != musicVisible else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) { musicVisible = v }
        layoutChanged()
    }

    // MARK: Toasts

    func show(_ t: Toast, for seconds: Double = 2.6) {
        toastWork?.cancel()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.68)) { toast = t }
        layoutChanged()
        scheduleToastEnd(after: seconds)
    }

    /// Volume-style HUD: keeps the same toast alive and just moves the bar.
    func showLevel(icon: String, title: String, level: Double) {
        toastWork?.cancel()
        if var t = toast, t.level != nil {
            t = Toast(id: t.id, icon: icon, tint: .white, title: title, detail: "", level: level)
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { toast = t }
        } else {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                toast = Toast(icon: icon, tint: .white, title: title, detail: "", level: level)
            }
        }
        layoutChanged()
        scheduleToastEnd(after: 1.6)
    }

    private func scheduleToastEnd(after seconds: Double) {
        let w = DispatchWorkItem { [weak self] in
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { self?.toast = nil }
            self?.layoutChanged()
        }
        toastWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: w)
    }

    func celebrate() { celebration += 1 }

    private func timerFinished() {
        if Prefs.bool(Prefs.timerSound) { NSSound(named: "Glass")?.play() }
        if Prefs.bool(Prefs.timerPausesMusic), music.isPlaying { music.playPause() }
        celebrate()
        show(Toast(icon: "bell.fill", tint: .orange, title: "Time's up!", detail: "Timer done",
                   detailIcon: "checkmark.circle.fill"), for: 4)
    }

    private func handle(_ e: SystemEvent) {
        switch e {
        case .chargingStarted(let level):
            guard Prefs.bool(Prefs.chargingToast) else { return }
            show(Toast(icon: "bolt.fill", tint: .green, title: "Charging", detail: "\(level)%",
                       detailIcon: SystemMonitor.batterySymbol(level: level, charging: true)))
        case .lowBattery(let level):
            guard Prefs.bool(Prefs.showBattery) else { return }
            show(Toast(icon: "battery.25percent", tint: .red, title: "Low Battery", detail: "\(level)%"), for: 3.5)
        case .micStarted(let app):
            guard Prefs.bool(Prefs.showMic) else { return }
            show(Toast(icon: "mic.fill", tint: .orange, title: "Microphone", detail: app ?? "In use"))
        case .cameraStarted:
            guard Prefs.bool(Prefs.showCamera) else { return }
            show(Toast(icon: "video.fill", tint: .green, title: "Camera", detail: "In use"))
        }
    }
}

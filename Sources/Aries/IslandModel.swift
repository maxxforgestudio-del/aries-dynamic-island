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
    case download
    case activity
    case music
    case toast(Toast)
}

enum IslandTab: String, CaseIterable, Identifiable {
    case call, home, music, notes, shelf, timer, tools, clipboard, mirror
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .call: return "phone.fill"
        case .home: return "house.fill"
        case .music: return "music.note"
        case .notes: return "note.text"
        case .shelf: return "tray.full.fill"
        case .timer: return "timer"
        case .tools: return "square.grid.2x2.fill"
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
    let downloads = DownloadsMonitor()
    let live = LiveActivityCenter()
    let focus = FocusModel()
    let tools = ToolsModel()
    let focusMode = FocusMonitor()
    private let extras = SystemExtras()

    enum Secondary: Hashable { case timer, download, activity, privacy, stopwatch }
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
    /// Little sideways bump when you swipe the island to skip.
    @Published private(set) var nudge: CGFloat = 0

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

        for pub in [live.objectWillChange.eraseToAnyPublisher(), focus.objectWillChange.eraseToAnyPublisher(),
                    tools.objectWillChange.eraseToAnyPublisher(), focusMode.objectWillChange.eraseToAnyPublisher()] {
            pub.receive(on: RunLoop.main)
                .sink { [weak self] in self?.objectWillChange.send(); self?.layoutChanged() }
                .store(in: &bag)
        }
        downloads.objectWillChange.receive(on: RunLoop.main)
            .sink { [weak self] in self?.objectWillChange.send(); self?.layoutChanged() }
            .store(in: &bag)
        music.$lyricsState.receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send(); self?.layoutChanged() }
            .store(in: &bag)

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
        downloads.onFinished = { [weak self] url in self?.downloadFinished(url) }
        downloads.setEnabled(Prefs.bool(Prefs.downloadsActivity))
        Updater.shared.onAvailable = { [weak self] v in
            guard let self else { return }
            if Prefs.bool(Prefs.autoInstallUpdates) {
                // Fully automatic: wait for a quiet moment (no call, island closed), then update.
                self.installWhenQuiet(v)
            } else {
                self.show(Toast(icon: "arrow.down.app.fill", tint: .blue, title: "Aries \(v) is here", detail: "Update",
                                detailIcon: "arrow.right.circle.fill"), for: 6)
            }
        }
        Updater.shared.startAutomaticChecks()
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
        focusMode.onChange = { [weak self] old, new in
            guard let self, Prefs.bool(Prefs.focusToasts) else { return }
            if let m = new {
                self.show(Toast(icon: m.symbol, tint: m.color, title: m.name, detail: "On", detailIcon: "circle.fill"), for: 2.6)
            } else if let m = old {
                self.show(Toast(icon: m.symbol, tint: .white.opacity(0.7), title: m.name, detail: "Off"), for: 2)
            }
        }
        focusMode.start()
        extras.onToast = { [weak self] t, secs in
            guard let self, !self.isExpanded else { return }
            self.show(t, for: secs)
        }
        extras.start()
        DesktopWidgets.shared.refresh(model: self)
        LockScreenWidgets.shared.start(model: self)
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
        if downloads.current != nil && Prefs.bool(Prefs.downloadsActivity) && !(musicVisible && music.track != nil) { return .download }
        if live.current != nil && !(musicVisible && music.track != nil) { return .activity }
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
        if Prefs.bool(Prefs.showTools) { t.append(.tools) }
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
            case .tools: h = 166
            case .clipboard: h = 214
            case .mirror: h = 196
            case .call: h = 92
            }
            return CGSize(width: max(W + 410, 600) * A11y.scale, height: (H + h) * A11y.scale)
        }
        switch compact {
        case .idle: return CGSize(width: W, height: H)
        case .indicators: return CGSize(width: W + 2 * 34, height: H)
        case .timer: return CGSize(width: W + 2 * 46, height: H)
        case .call: return CGSize(width: W + 2 * 52, height: H)
        case .music:
            let w = W + 2 * (timer.isActive ? 58 : 44)
            return showsLyricStrip ? CGSize(width: max(w, W + 190), height: H + 26) : CGSize(width: w, height: H)
        case .download: return CGSize(width: W + 2 * 60, height: H)
        case .activity:
            let chars = CGFloat(max((live.current?.title.count ?? 0), (live.current?.subtitle.count ?? 0)))
            return CGSize(width: W + 2 * min(170, max(80, 40 + chars * 7.2)), height: H)
        case .toast(let t):
            let chars = CGFloat(max(t.title.count, t.detail.count + (t.detailIcon == nil ? 0 : 3)))
            let wing = min(185, max(104, 50 + chars * 7.4))
            return CGSize(width: W + 2 * wing, height: H)
        }
    }

    var totalSize: CGSize { CGSize(width: bodySize.width + ear * 2, height: bodySize.height) }

    var layoutKey: String {
        "\(isExpanded)-\(compact)-\(tab)-\(musicPanel)-\(music.track != nil)-\(timer.isActive)-\(showsLyricStrip)-\(String(describing: secondary))"
    }

    /// The slim live-lyrics line under the notch while a song with synced lyrics plays.
    var showsLyricStrip: Bool {
        Prefs.bool(Prefs.liveLyrics) && music.isPlaying && music.lyrics?.synced == true
    }

    // MARK: Gestures

    /// Swipe left/right = next/previous. Scroll up/down on the closed island = volume.
    func swipe(next: Bool) {
        guard music.track != nil else { return }
        next ? music.next() : music.previous()
        if Prefs.bool(Prefs.haptics) {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }
        guard !A11y.reduceMotion else { return }
        withAnimation(.spring(response: 0.18, dampingFraction: 0.5)) { nudge = next ? -14 : 14 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
            withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) { self?.nudge = 0 }
        }
    }

    func scrollVolume(by delta: Int) {
        guard music.track != nil else { return }
        let v = max(0, min(100, music.volume + delta))
        guard v != music.volume else { return }
        music.setVolume(v)
        showLevel(icon: AudioMonitor.volumeSymbol(Float(v) / 100, muted: v == 0),
                  title: music.source == .appleMusic ? "Music" : "Spotify", level: Double(v) / 100)
    }

    private func downloadFinished(_ url: URL) {
        if Prefs.bool(Prefs.downloadsToShelf) { shelf.add([url]) }
        show(Toast(icon: "arrow.down.circle.fill", tint: .green, title: url.lastPathComponent,
                   detail: Prefs.bool(Prefs.downloadsToShelf) ? "On your Shelf" : "Downloaded",
                   detailIcon: "checkmark.circle.fill"), for: 3.5)
    }

    private func layoutChanged() {
        DispatchQueue.main.async { self.onLayoutChange?() }
    }

    // MARK: Hover / expand

    func setHovering(_ inside: Bool) {
        guard inside != hovering else { return }
        hovering = inside
        if Prefs.bool(Prefs.hoverBounce) && !A11y.reduceMotion {
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
        if let t = toast, t.icon == "hand.raised.fill" {
            AppDelegate.shared.openSettings(pane: "permissions")
            return
        }
        if let t = toast, t.icon == "arrow.down.app.fill" {
            AppDelegate.shared.openSettings(pane: "updates")
            return
        }
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
        A11y.announce([t.title, t.detail].filter { !$0.isEmpty }.joined(separator: ", "))
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

    // MARK: Second activity (split-off bubble)

    /// When something else is running alongside the main activity, it splits into a bubble.
    var secondary: Secondary? {
        guard !isExpanded, toast == nil else { return nil }
        switch compact {
        case .music, .call, .download, .activity, .timer:
            if compact != .timer, timer.isActive { return .timer }
            if compact != .download, downloads.current != nil, Prefs.bool(Prefs.downloadsActivity) { return .download }
            if compact != .activity, live.current != nil { return .activity }
            if focus.stopwatchRunning { return .stopwatch }
            if hasIndicators, compact != .call { return .privacy }
            return nil
        default:
            // A stopwatch running on its own gets its bubble beside the notch.
            return focus.stopwatchRunning ? .stopwatch : nil
        }
    }

    func openSecondary(_ s: Secondary) {
        switch s {
        case .timer, .stopwatch: expand(to: .timer)
        case .download: expand(to: .shelf)
        case .activity, .privacy: expand(to: .home)
        }
    }

    // MARK: aries:// links (Live Activities for Shortcuts, scripts and other apps)

    func handle(url: URL) {
        guard url.scheme == "aries" else { return }
        let q = Dictionary((URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
            .map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { $1 })
        let action = ([url.host ?? ""] + url.pathComponents.filter { $0 != "/" }).joined(separator: "/")
        switch action {
        case "activity", "activity/start", "activity/update":
            let id = q["id"] ?? q["title"] ?? UUID().uuidString
            live.upsert(LiveActivity(id: id, title: q["title"] ?? "Live Activity", subtitle: q["subtitle"] ?? "",
                                     icon: q["icon"] ?? "sparkles", color: LiveActivityCenter.color(q["color"]),
                                     progress: q["progress"].flatMap(Double.init).map { min(1, max(0, $0)) }))
        case "activity/end":
            if let id = q["id"] { live.end(id) } else { live.endAll() }
        case "toast":
            show(Toast(icon: q["icon"] ?? "bell.fill", tint: LiveActivityCenter.color(q["color"] ?? "white"),
                       title: q["title"] ?? "Aries", detail: q["subtitle"] ?? ""), for: Double(q["seconds"] ?? "") ?? 3)
        case "timer":
            timer.start(minutes: Double(q["minutes"] ?? "") ?? 5)
        case "focus":
            focus.startFocus(timer)
        case "stopwatch":
            focus.toggleStopwatch()
        case "awake":
            tools.keepAwake(minutes: q["minutes"].flatMap(Double.init))
            confirm("cup.and.saucer.fill", "Mac stays awake")
        case "awake/off":
            tools.stopAwake()
        case "note":
            if let t = q["text"], !t.isEmpty { notes.add(t); confirm("note.text", "Note saved") } else { newNote() }
        case "open":
            expand(to: IslandTab(rawValue: q["tab"] ?? "") ?? .home)
        case "close":
            collapse()
        case "settings":
            AppDelegate.shared.openSettings(pane: q["pane"] ?? "general")
        case "whatsnew":
            AppDelegate.shared.openWhatsNew()
        case "welcome":
            AppDelegate.shared.openWelcome()
        case "update-experience":
            AppDelegate.shared.openUpdateExperience()
        case "windows/close":
            AppDelegate.shared.closeAuxWindows()
        case "style":
            // aries://style?name=aquatic | crystal | classic
            if let n = q["name"] { withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { UserDefaults.standard.set(n, forKey: Prefs.islandStyle) } }
        case "lyrics":
            // aries://lyrics?style=vinyl&side=none (style: lyrics | vinyl | karaoke; side: lyrics | queue | artist | album | none)
            if let st = q["style"], let style = LyricsStyle(rawValue: st) { LyricsPrefs.style = style }
            if let sd = q["side"], PlayerSide(rawValue: sd) != nil {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) { UserDefaults.standard.set(sd, forKey: "playerSide") }
            }
            AppDelegate.shared.openLyrics()
        case "lyrics/close":
            AppDelegate.shared.closeLyrics()
        case "play", "pause", "playpause":
            music.playPause()
        case "next": music.next()
        case "previous": music.previous()
        default:
            expand()
        }
        layoutChanged()
    }

    private func installWhenQuiet(_ v: String) {
        // No downloadable build attached to the release: just let the user know, never open a browser on its own.
        guard Updater.shared.canInstallInPlace else {
            show(Toast(icon: "arrow.down.app.fill", tint: .blue, title: "Aries \(v) is here", detail: "Update",
                       detailIcon: "arrow.right.circle.fill"), for: 6)
            return
        }
        guard calls.call == nil, !isExpanded, !isEditing else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in self?.installWhenQuiet(v) }
            return
        }
        show(Toast(icon: "sparkles", tint: .cyan, title: "Updating to Aries \(v)", detail: "One moment"), for: 4)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { Updater.shared.install() }
    }

    private func timerFinished() {
        if Prefs.bool(Prefs.timerSound) { NSSound(named: "Glass")?.play() }
        if let (icon, text) = focus.timerEnded(timer) {
            show(Toast(icon: icon, tint: .orange, title: text, detail: focus.phase == .rest ? "\(Int(focus.breakMinutes)) min" : "\(Int(focus.focusMinutes)) min"), for: 4)
            return
        }
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

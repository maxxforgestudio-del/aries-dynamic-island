import AppKit
import SwiftUI

// MARK: - Widget kinds

enum AriesWidget: String, CaseIterable, Identifiable {
    case nowPlaying, clock, weather, calendar, battery, todos
    var id: String { rawValue }

    var title: String {
        switch self {
        case .nowPlaying: return "Now Playing"
        case .clock: return "Clock"
        case .weather: return "Weather"
        case .calendar: return "Up Next"
        case .battery: return "Battery"
        case .todos: return "To-Dos"
        }
    }
    var icon: String {
        switch self {
        case .nowPlaying: return "music.note"
        case .clock: return "clock.fill"
        case .weather: return "cloud.sun.fill"
        case .calendar: return "calendar"
        case .battery: return "battery.75percent"
        case .todos: return "checklist"
        }
    }
    var size: CGSize {
        switch self {
        case .nowPlaying: return CGSize(width: 330, height: 158)
        case .todos: return CGSize(width: 330, height: 158)
        default: return CGSize(width: 158, height: 158)
        }
    }
    var prefKey: String { "widget.\(rawValue)" }
    var isOn: Bool { UserDefaults.standard.object(forKey: prefKey) as? Bool ?? [.nowPlaying, .clock, .weather, .calendar].contains(self) }
}

// MARK: - Shared widget views (desktop + lock screen)

struct WidgetCard<Content: View>: View {
    var size: CGSize
    var tint: Color? = nil
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .background {
                ZStack {
                    GlassBackdrop(material: .hudWindow)
                    if let tint { LinearGradient(colors: [tint.opacity(0.35), tint.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing) }
                    Color.black.opacity(0.12)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(.white.opacity(0.14), lineWidth: 1))
            .environment(\.colorScheme, .dark)
    }
}

struct WidgetView: View {
    let kind: AriesWidget
    let model: IslandModel

    var body: some View {
        switch kind {
        case .nowPlaying: NowPlayingWidget(music: model.music)
        case .clock: ClockWidget()
        case .weather: WeatherWidget(weather: model.weather)
        case .calendar: CalendarWidget(calendar: model.calendar)
        case .battery: BatteryWidget(system: model.system)
        case .todos: TodoWidget(notes: model.notes)
        }
    }
}

struct NowPlayingWidget: View {
    @ObservedObject var music: MusicController
    var body: some View {
        WidgetCard(size: AriesWidget.nowPlaying.size, tint: music.track != nil ? music.accent : nil) {
            if let t = music.track {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        ArtworkView(image: music.artwork, size: 64, radius: 12, accent: music.accent)
                            .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.title).font(.system(size: 15, weight: .bold)).lineLimit(1)
                            Text(t.artist).font(.system(size: 13)).opacity(0.65).lineLimit(1)
                            if let line = currentLine {
                                Text(line).font(.system(size: 11.5, weight: .semibold)).opacity(0.85).lineLimit(1)
                                    .padding(.top, 2).transition(.opacity)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        let p = music.duration > 0 ? music.position / music.duration : 0
                        Capsule().fill(.white.opacity(0.2)).frame(height: 4)
                            .overlay(alignment: .leading) {
                                GeometryReader { g in Capsule().fill(.white).frame(width: g.size.width * p) }
                            }
                    }
                    .frame(height: 4)
                    HStack(spacing: 30) {
                        Spacer()
                        Button { music.previous() } label: { Image(systemName: "backward.fill") }
                        Button { music.playPause() } label: {
                            Image(systemName: music.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 22))
                                .contentTransition(.symbolEffect(.replace))
                        }
                        Button { music.next() } label: { Image(systemName: "forward.fill") }
                        Spacer()
                    }
                    .font(.system(size: 16))
                    .buttonStyle(.plain)
                }
                .foregroundStyle(.white)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Not Playing", systemImage: "music.note").font(.system(size: 13, weight: .bold)).opacity(0.6)
                    Spacer()
                    Text("Play something in Spotify or Music").font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.white)
            }
        }
    }

    private var currentLine: String? {
        guard let i = music.clock.lineIndex, let l = music.lyrics, i < l.lines.count else { return nil }
        let s = l.lines[i].text
        return s.isEmpty ? nil : "♪ " + s
    }
}

struct ClockWidget: View {
    var body: some View {
        WidgetCard(size: AriesWidget.clock.size) {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                VStack(alignment: .leading, spacing: 0) {
                    Text(ctx.date, format: .dateTime.weekday(.wide)).font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.red)
                    Text(ctx.date, format: .dateTime.day()).font(.system(size: 44, weight: .light))
                    Spacer()
                    Text(ctx.date, format: .dateTime.hour().minute()).font(.system(size: 24, weight: .bold, design: .rounded))
                        .monospacedDigit().contentTransition(.numericText())
                    Text(IslandModel.greeting(ctx.date)).font(.system(size: 11.5, weight: .semibold)).opacity(0.55)
                }
                .foregroundStyle(.white)
            }
        }
    }
}

struct WeatherWidget: View {
    @ObservedObject var weather: WeatherModel
    var body: some View {
        WidgetCard(size: AriesWidget.weather.size, tint: weather.isDay ? .blue : .indigo) {
            VStack(alignment: .leading, spacing: 2) {
                Text(weather.city.isEmpty ? "Weather" : weather.city).font(.system(size: 13, weight: .bold)).lineLimit(1)
                Text(weather.temperature.map { "\(Int($0.rounded()))°" } ?? "--")
                    .font(.system(size: 42, weight: .light))
                Spacer()
                Image(systemName: weather.symbol).symbolRenderingMode(.multicolor).font(.system(size: 18))
                if let h = weather.high, let l = weather.low {
                    Text("H:\(Int(h.rounded()))°  L:\(Int(l.rounded()))°").font(.system(size: 12, weight: .semibold))
                }
            }
            .foregroundStyle(.white)
        }
    }
}

struct CalendarWidget: View {
    @ObservedObject var calendar: CalendarModel
    var body: some View {
        WidgetCard(size: AriesWidget.calendar.size) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Up Next", systemImage: "calendar").font(.system(size: 12.5, weight: .bold)).foregroundStyle(.red)
                if let e = calendar.upcoming.first {
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: 2).fill(e.color).frame(width: 26, height: 4)
                    Text(e.title).font(.system(size: 15, weight: .bold)).lineLimit(2)
                    Text(CalendarModel.relative(e.start)).font(.system(size: 12.5, weight: .semibold)).opacity(0.6)
                    Text(e.start, format: .dateTime.hour().minute()).font(.system(size: 12)).opacity(0.5)
                } else {
                    Spacer()
                    Text(calendar.authorized ? "Nothing else today" : "Allow Calendar in Aries Settings")
                        .font(.system(size: 14, weight: .semibold)).opacity(0.75)
                }
            }
            .foregroundStyle(.white)
        }
    }
}

struct BatteryWidget: View {
    @ObservedObject var system: SystemMonitor
    var body: some View {
        WidgetCard(size: AriesWidget.battery.size) {
            let level = system.batteryLevel ?? 100
            let c: Color = system.isCharging ? .green : (level <= 20 ? .red : .white)
            VStack(spacing: 10) {
                ZStack {
                    Circle().stroke(.white.opacity(0.15), lineWidth: 8)
                    Circle().trim(from: 0, to: Double(level) / 100)
                        .stroke(c, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: system.isCharging ? "bolt.fill" : "laptopcomputer")
                        .font(.system(size: 22, weight: .semibold)).foregroundStyle(c)
                }
                .frame(width: 78, height: 78)
                Text(system.batteryLevel.map { "\($0)%" } ?? "Power Adapter")
                    .font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct TodoWidget: View {
    @ObservedObject var notes: NotesStore
    var body: some View {
        WidgetCard(size: AriesWidget.todos.size, tint: .yellow) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("To-Dos", systemImage: "checklist").font(.system(size: 13, weight: .bold)).foregroundStyle(.yellow)
                    Spacer()
                    Text("\(notes.openCount) open").font(.system(size: 11.5, weight: .semibold)).opacity(0.55)
                }
                let open = notes.sorted.filter { !$0.done }.prefix(4)
                if open.isEmpty {
                    Spacer()
                    Text("All done 🎉").font(.system(size: 15, weight: .semibold))
                } else {
                    ForEach(Array(open)) { n in
                        Button { withAnimation(.spring) { notes.toggle(n) } } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "circle").foregroundStyle(.yellow)
                                Text(n.text).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .font(.system(size: 13.5, weight: .medium))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
        }
    }
}

// MARK: - Desktop widgets

private final class WidgetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
}

/// Widgets that sit on your desktop, below your windows (like macOS desktop widgets).
/// Drag any widget to move it; Aries remembers where you put it.
final class DesktopWidgets {
    static let shared = DesktopWidgets()
    private var panels: [AriesWidget: NSPanel] = [:]
    private var observers: [NSObjectProtocol] = []

    func refresh(model: IslandModel) {
        let on = Prefs.bool(Prefs.desktopWidgets)
        for kind in AriesWidget.allCases {
            if on && kind.isOn {
                if panels[kind] == nil { panels[kind] = makePanel(kind, model: model) }
                panels[kind]?.orderFrontRegardless()
            } else if let p = panels[kind] {
                p.orderOut(nil); panels[kind] = nil
            }
        }
    }

    func resetPositions(model: IslandModel) {
        for k in AriesWidget.allCases { UserDefaults.standard.removeObject(forKey: k.prefKey + ".origin") }
        panels.values.forEach { $0.orderOut(nil) }
        panels.removeAll()
        refresh(model: model)
    }

    private func defaultOrigin(_ kind: AriesWidget) -> NSPoint {
        // A tidy 2-column grid in the top-right corner of the main screen.
        let vf = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let left = vf.maxX - 24 - 330, right = vf.maxX - 24 - 158, gap: CGFloat = 14, h: CGFloat = 158
        let (col, row): (Int, Int)
        switch kind {
        case .nowPlaying: (col, row) = (0, 0)
        case .clock: (col, row) = (0, 1)
        case .weather: (col, row) = (1, 1)
        case .calendar: (col, row) = (0, 2)
        case .battery: (col, row) = (1, 2)
        case .todos: (col, row) = (0, 3)
        }
        return NSPoint(x: col == 0 ? left : right, y: vf.maxY - 24 - CGFloat(row + 1) * h - CGFloat(row) * gap)
    }

    private func makePanel(_ kind: AriesWidget, model: IslandModel) -> NSPanel {
        let size = kind.size
        let p = WidgetPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovableByWindowBackground = true
        p.hidesOnDeactivate = false
        p.contentView = NSHostingView(rootView: WidgetView(kind: kind, model: model))
        let key = kind.prefKey + ".origin"
        if let s = UserDefaults.standard.string(forKey: key) { p.setFrameOrigin(NSPointFromString(s)) }
        else { p.setFrameOrigin(defaultOrigin(kind)) }
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: p, queue: .main) { _ in
            UserDefaults.standard.set(NSStringFromPoint(p.frame.origin), forKey: key)
        })
        return p
    }
}

// MARK: - Lock Screen

/// Shows Now Playing and a row of widgets on the Mac's Lock Screen, like iPhone.
/// macOS has no public API for this, so it uses the same private window-server
/// mechanism other notch apps use. If that isn't available, nothing is shown.
final class LockScreenWidgets {
    static let shared = LockScreenWidgets()
    private var window: NSWindow?
    private weak var model: IslandModel?
    private var space: Int32 = 0
    private var conn: Int32 = 0
    private var locked = false
    private var pollTimer: Timer?

    // Signatures match the window server's C API (ints, not 64-bit ids).
    private typealias MainConn = @convention(c) () -> Int32
    private typealias SpaceCreate = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias SetLevel = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias AddWindows = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32

    private lazy var skylight: UnsafeMutableRawPointer? =
        dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW)
    private func fn<T>(_ name: String, _: T.Type) -> T? {
        guard let h = skylight, let p = dlsym(h, name) else { return nil }
        return unsafeBitCast(p, to: T.self)
    }

    var isSupported: Bool {
        fn("SLSMainConnectionID", MainConn.self) != nil && fn("SLSSpaceCreate", SpaceCreate.self) != nil
            && fn("SLSSpaceSetAbsoluteLevel", SetLevel.self) != nil && fn("SLSShowSpaces", ShowSpaces.self) != nil
            && fn("SLSSpaceAddWindowsAndRemoveFromSpaces", AddWindows.self) != nil
    }

    func start(model: IslandModel) {
        self.model = model
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in self?.setLocked(true) }
        dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in self?.setLocked(false) }
        // Backup: ask the window server whether the screen is locked, in case a notification is missed.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            let d = CGSessionCopyCurrentDictionary() as? [String: Any]
            let isLocked = (d?["CGSSessionScreenIsLocked"] as? Bool) ?? ((d?["CGSSessionScreenIsLocked"] as? Int) == 1)
            self?.setLocked(isLocked)
        }
    }

    private func setLocked(_ l: Bool) {
        guard l != locked else { return }
        locked = l
        l ? show() : hide()
    }

    /// The special window-server space that sits above the Lock Screen (level 400, the same one
    /// Notification Center uses while locked).
    private func prepareSpace() -> Bool {
        if space != 0 { return true }
        guard let main = fn("SLSMainConnectionID", MainConn.self), let create = fn("SLSSpaceCreate", SpaceCreate.self),
              let level = fn("SLSSpaceSetAbsoluteLevel", SetLevel.self), let showSpaces = fn("SLSShowSpaces", ShowSpaces.self)
        else { return false }
        conn = main()
        space = create(conn, 1, 0)
        guard space != 0 else { return false }
        _ = level(conn, space, 400)
        _ = showSpaces(conn, [space] as CFArray)
        return true
    }

    func show() {
        guard Prefs.bool(Prefs.lockScreenWidgets), isSupported, let model, prepareSpace() else { return }
        let screen = NSScreen.main ?? NSScreen.screens[0]
        if window == nil {
            let w = LockWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = false
            w.isReleasedWhenClosed = false
            w.canBecomeVisibleWithoutLogin = true
            w.level = NSWindow.Level(rawValue: Int(Int32.max - 2))
            w.collectionBehavior = [.fullScreenAuxiliary, .stationary, .canJoinAllSpaces, .ignoresCycle]
            w.contentView = NSHostingView(rootView: LockScreenView(model: model, music: model.music))
            window = w
        }
        guard let w = window, let add = fn("SLSSpaceAddWindowsAndRemoveFromSpaces", AddWindows.self) else { return }
        w.setFrame(screen.frame, display: true)
        w.alphaValue = 0
        _ = add(conn, space, [w.windowNumber] as CFArray, 7)
        w.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.5; w.animator().alphaValue = 1 }
    }

    func hide() {
        guard let w = window else { return }
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.2; w.animator().alphaValue = 0 }, completionHandler: {
            w.orderOut(nil)
        })
    }
}

private final class LockWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

private struct LockScreenView: View {
    let model: IslandModel
    @ObservedObject var music: MusicController

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 14) {
                HStack(spacing: 14) {
                    WeatherWidget(weather: model.weather)
                    CalendarWidget(calendar: model.calendar)
                    BatteryWidget(system: model.system)
                }
                .scaleEffect(0.82)
                .frame(height: 158 * 0.82)
                if music.track != nil {
                    NowPlayingWidget(music: music)
                        .scaleEffect(1.12)
                        .padding(.top, 14)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: geo.size.width)
            .padding(.top, geo.size.height * 0.30)
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: music.track?.id)
        }
        .environment(\.colorScheme, .dark)
    }
}

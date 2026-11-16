import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct IslandRootView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var music: MusicController
    @AppStorage(Prefs.showNotes) private var showNotes = true
    @AppStorage(Prefs.notesIntensity) private var intensity = 0.35

    var body: some View {
        ZStack(alignment: .top) {
            if showNotes {
                MusicNotesView(
                    islandWidth: model.totalSize.width,
                    islandHeight: model.totalSize.height,
                    color: music.accent,
                    intensity: intensity,
                    active: music.isPlaying && !model.isExpanded && model.compact == .music && !A11y.reduceMotion
                )
                .allowsHitTesting(false)
            }
            IslandView(model: model, music: music)
            if let sec = model.secondary {
                let d = model.notchSize.height
                SecondaryBubble(model: model, kind: sec, diameter: d)
                    .offset(x: model.totalSize.width / 2 + 7 + d / 2 - 0.5 + model.nudge)
                    .id(sec)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.2, anchor: .leading).combined(with: .opacity).combined(with: .offset(x: -d)),
                        removal: .scale(scale: 0.2, anchor: .leading).combined(with: .opacity).combined(with: .offset(x: -d))))
            }
            if !A11y.reduceMotion {
                ConfettiView(trigger: model.celebration, originY: model.totalSize.height - 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.5, dampingFraction: 0.68), value: model.secondary)
        .environment(\.colorScheme, .dark)
    }
}

struct IslandView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var music: MusicController
    @AppStorage(Prefs.musicGlow) private var musicGlow = true
    @Namespace private var ns

    var body: some View {
        let shape = NotchShape(topRadius: model.ear, bottomRadius: model.bottomRadius)
        let size = model.totalSize
        let glow = musicGlow && !model.isExpanded && model.compact == .music && music.isPlaying
        let squish = model.isHovering && !model.isExpanded && !A11y.reduceMotion
        let k = model.isExpanded ? A11y.scale : 1

        ZStack(alignment: .top) {
            IslandSurface(shape: shape, expanded: model.isExpanded, notchHeight: model.notchSize.height, accent: music.accent)
            content
                .padding(.horizontal, model.ear)
                .frame(width: size.width / k, height: size.height / k, alignment: .top)
                .scaleEffect(k, anchor: .top)
                .frame(width: size.width, height: size.height, alignment: .top)
            if model.dropTargeted {
                shape.stroke(music.accent.opacity(0.9), lineWidth: 2)
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .background {
            if glow && !A11y.reduceMotion {
                shape.fill(.black)
                    .phaseAnimator([0.12, 0.5]) { c, p in
                        c.shadow(color: music.accent.opacity(p), radius: 11, y: 1)
                    } animation: { _ in .easeInOut(duration: 1.7) }
            }
        }
        .shadow(color: .black.opacity(model.isExpanded ? 0.45 : 0), radius: 22, y: 10)
        .environment(\.islandNamespace, ns)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Aries Dynamic Island")
        .scaleEffect(x: squish ? 1.05 : 1, y: squish ? 1.12 : 1, anchor: .top)
        .offset(x: model.nudge)
        .contentShape(shape)
        .onTapGesture { model.tap() }
        .onDrop(of: [.fileURL], isTargeted: $model.dropTargeted) { providers in
            for p in providers {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async { model.shelf.add([url]) }
                }
            }
            if Prefs.bool(Prefs.haptics) {
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            }
            return true
        }
        .contextMenu {
            Button("Show Lyrics") { AppDelegate.shared.openLyrics() }
            Button("Settings…") { AppDelegate.shared.openSettings() }
            Divider()
            Button("Quit Aries") { NSApp.terminate(nil) }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.74), value: model.layoutKey)
    }

    @ViewBuilder private var content: some View {
        if model.isExpanded {
            ExpandedView(model: model, music: music)
                .transition(.asymmetric(
                    insertion: AnyTransition.islandContent(scale: 0.88)
                        .animation(.spring(response: 0.45, dampingFraction: 0.78).delay(0.04)),
                    removal: AnyTransition.islandContent(scale: 0.94).animation(.easeOut(duration: 0.16))))
        } else {
            switch model.compact {
            case .music:
                CompactMusicView(music: music, timer: model.timer, notch: model.notchSize, strip: model.showsLyricStrip)
                    .transition(.opacity.combined(with: .blurReplace))
            case .timer:
                CompactTimerView(timer: model.timer, notch: model.notchSize)
                    .transition(.opacity.combined(with: .blurReplace))
            case .download:
                CompactDownloadView(downloads: model.downloads, notch: model.notchSize)
                    .transition(.opacity.combined(with: .blurReplace))
            case .activity:
                CompactActivityView(live: model.live, notch: model.notchSize)
                    .transition(.opacity.combined(with: .blurReplace))
            case .call:
                CompactCallView(calls: model.calls, notch: model.notchSize)
                    .transition(.opacity.combined(with: .blurReplace))
            case .indicators:
                CompactIndicatorsView(system: model.system, notch: model.notchSize)
                    .transition(.opacity)
            case .toast(let t):
                ToastView(toast: t, notch: model.notchSize)
                    .id(t.id)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            case .idle:
                Color.clear
            }
        }
    }
}

// MARK: - Compact

struct Wings<L: View, R: View>: View {
    let notch: CGSize
    @ViewBuilder var left: L
    @ViewBuilder var right: R
    var body: some View {
        HStack(spacing: 0) {
            left.frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: notch.width)
            right.frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: notch.height)
    }
}

struct CompactMusicView: View {
    @ObservedObject var music: MusicController
    @ObservedObject var timer: TimerModel
    let notch: CGSize
    var strip = false
    @AppStorage(Prefs.showVisualizer) private var showVisualizer = true

    var body: some View {
        VStack(spacing: 0) {
            wings
            if strip {
                LyricStrip(music: music, clock: music.clock)
                    .frame(height: 22)
                    .padding(.horizontal, 16)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: strip)
    }

    private var wings: some View {
        Wings(notch: notch) {
            ArtworkView(image: music.artwork, size: notch.height - 10, radius: 6, accent: music.accent)
                .islandMatched("art")
                .id(music.track?.id)
                .transition(.scale(scale: 0.3).combined(with: .opacity))
                .padding(.leading, 9)
                .opacity(music.isPlaying ? 1 : 0.6)
                .scaleEffect(music.isPlaying ? 1 : 0.85)
        } right: {
            Group {
                if false {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        Text(TimerModel.format(timer.remaining(at: ctx.date)))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.orange)
                            .monospacedDigit()
                            .lineLimit(1)
                            .fixedSize()
                    }
                } else if showVisualizer {
                    VisualizerView(isPlaying: music.isPlaying, color: music.accent)
                } else {
                    Image(systemName: music.isPlaying ? "play.fill" : "pause.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(music.accent)
                }
            }
            .padding(.trailing, 12)
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.6), value: music.track?.id)
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: music.isPlaying)
    }
}

/// The current lyric, gliding along under the notch.
struct LyricStrip: View {
    @ObservedObject var music: MusicController
    @ObservedObject var clock: LyricsClock

    var body: some View {
        let line: String = {
            guard let l = music.lyrics, l.synced, let i = clock.lineIndex else { return "" }
            return l.lines[i].text
        }()
        ZStack {
            if line.isEmpty {
                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle().fill(.white.opacity(0.5)).frame(width: 4, height: 4)
                            .phaseAnimator([0.35, 1.0]) { c, p in c.opacity(p) } animation: { _ in
                                .easeInOut(duration: 0.6).delay(Double(i) * 0.2)
                            }
                    }
                }
                .transition(.opacity)
            } else {
                Text(line)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [.white, music.accent], startPoint: .leading, endPoint: .trailing))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .id(line)
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.9)),
                                            removal: .move(edge: .top).combined(with: .opacity)))
            }
        }
        .frame(maxWidth: .infinity)
        .clipped()
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: line)
    }
}

struct CompactDownloadView: View {
    @ObservedObject var downloads: DownloadsMonitor
    let notch: CGSize

    var body: some View {
        let item = downloads.current
        Wings(notch: notch) {
            ZStack {
                Circle().stroke(.green.opacity(0.25), lineWidth: 2.5)
                if let p = item?.progress {
                    Circle().trim(from: 0, to: p)
                        .stroke(.green, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.4), value: p)
                } else {
                    Circle().trim(from: 0, to: 0.3)
                        .stroke(.green, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .phaseAnimator([0.0, 360.0]) { c, a in c.rotationEffect(.degrees(a)) } animation: { _ in .linear(duration: 1).repeatForever(autoreverses: false) }
                }
                Image(systemName: "arrow.down")
                    .font(.system(size: 7, weight: .black))
                    .foregroundStyle(.green)
            }
            .frame(width: 16, height: 16)
            .padding(.leading, 12)
        } right: {
            Group {
                if let p = item?.progress {
                    Text("\(Int(p * 100))%")
                } else {
                    Text(DownloadsMonitor.format(item?.bytes ?? 0))
                }
            }
            .font(.system(size: 11.5, weight: .bold, design: .rounded))
            .foregroundStyle(.green)
            .monospacedDigit()
            .contentTransition(.numericText())
            .lineLimit(1)
            .fixedSize()
            .padding(.trailing, 12)
            .help(item?.name ?? "")
        }
    }
}

struct CompactTimerView: View {
    @ObservedObject var timer: TimerModel
    let notch: CGSize
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            Wings(notch: notch) {
                ZStack {
                    Circle().stroke(.orange.opacity(0.25), lineWidth: 2.5)
                    Circle().trim(from: 0, to: 1 - timer.progress(at: ctx.date))
                        .stroke(.orange, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.5), value: ctx.date)
                    Image(systemName: timer.isRunning ? "timer" : "pause.fill")
                        .font(.system(size: 7, weight: .black))
                        .foregroundStyle(.orange)
                }
                .frame(width: 15, height: 15)
                .padding(.leading, 12)
            } right: {
                Text(TimerModel.format(timer.remaining(at: ctx.date)))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.orange)
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.snappy, value: Int(timer.remaining(at: ctx.date)))
                    .padding(.trailing, 12)
            }
        }
    }
}

struct CompactIndicatorsView: View {
    @ObservedObject var system: SystemMonitor
    let notch: CGSize
    var body: some View {
        Wings(notch: notch) {
            HStack(spacing: 5) {
                if system.micActive && Prefs.bool(Prefs.showMic) {
                    Image(systemName: "mic.fill").foregroundStyle(.orange)
                        .symbolEffect(.pulse)
                }
                if system.cameraActive && Prefs.bool(Prefs.showCamera) {
                    Image(systemName: "video.fill").foregroundStyle(.green)
                }
            }
            .font(.system(size: 11, weight: .semibold))
            .padding(.leading, 10)
        } right: {
            Circle()
                .fill(system.cameraActive ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
                .shadow(color: (system.cameraActive ? Color.green : Color.orange).opacity(0.8), radius: 4)
                .phaseAnimator([1.0, 0.55]) { c, p in c.opacity(p) } animation: { _ in .easeInOut(duration: 1.1) }
                .padding(.trailing, 12)
        }
    }
}

struct ToastView: View {
    let toast: Toast
    let notch: CGSize
    @ViewState private var swapped = false
    @ViewState private var appeared = false

    var body: some View {
        Wings(notch: notch) {
            HStack(spacing: 6) {
                if let img = toast.image {
                    ArtworkView(image: img, size: notch.height - 12, radius: 5)
                        .scaleEffect(appeared ? 1 : 0.4)
                } else {
                    Image(systemName: (toast.fromIcon != nil && !swapped) ? toast.fromIcon! : toast.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(toast.tint)
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.bounce, value: appeared)
                        .frame(width: 18)
                }
                Text(toast.title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .padding(.leading, 12)
        } right: {
            Group {
                if let level = toast.level {
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.18))
                        Capsule().fill(.white)
                            .frame(width: max(6, 84 * level))
                    }
                    .frame(width: 84, height: 6)
                    .animation(.spring(response: 0.25, dampingFraction: 0.75), value: level)
                } else {
                    HStack(spacing: 5) {
                        Text(toast.detail)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(toast.tint == .white ? .white.opacity(0.7) : toast.tint)
                            .lineLimit(1)
                        if let i = toast.detailIcon {
                            Image(systemName: i)
                                .font(.system(size: 13))
                                .foregroundStyle(toast.tint == .white ? .green : toast.tint)
                        }
                    }
                }
            }
            .padding(.trailing, 13)
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.55)) { appeared = true }
            if toast.fromIcon != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { swapped = true }
                }
            }
        }
    }
}

// MARK: - Expanded

struct ExpandedView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var music: MusicController

    var body: some View {
        VStack(spacing: 0) {
            Wings(notch: model.notchSize) {
                TabBar(model: model).padding(.leading, 16)
            } right: {
                StatusCluster(system: model.system, tools: model.tools, focus: model.focusMode).padding(.trailing, 18)
            }
            ZStack(alignment: .top) {
                switch model.tab {
                case .call: CallTab(calls: model.calls).transition(tabTransition)
                case .home: HomeTab(model: model, music: music, calendar: model.calendar, weather: model.weather).transition(tabTransition)
                case .music: MusicTab(model: model, music: music).transition(tabTransition)
                case .notes: NotesTab(model: model, notes: model.notes).transition(tabTransition)
                case .shelf: ShelfTab(model: model, shelf: model.shelf).transition(tabTransition)
                case .timer: TimerTab(timer: model.timer, focus: model.focus).transition(tabTransition)
                case .tools: ToolsTab(model: model, tools: model.tools).transition(tabTransition)
                case .clipboard: ClipboardTab(clipboard: model.clipboard, model: model).transition(tabTransition)
                case .mirror: MirrorTab(camera: model.mirror).transition(tabTransition)
                }
                if let b = model.banner {
                    HStack(spacing: 6) {
                        Image(systemName: b.0).symbolEffect(.bounce, value: b.1)
                        Text(b.1).lineLimit(1)
                        if b.2 { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                    }
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Capsule().fill(Color(white: 0.16)).shadow(radius: 8))
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 2)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: model.banner?.1)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private var tabTransition: AnyTransition {
        .asymmetric(insertion: .opacity.combined(with: .offset(y: 10)).combined(with: .scale(scale: 0.97)),
                    removal: .opacity.animation(.easeOut(duration: 0.1)))
    }
}

private struct TabBar: View {
    @ObservedObject var model: IslandModel
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            ForEach(model.tabs) { t in
                let selected = model.tab == t
                Button { model.select(t) } label: {
                    Image(systemName: t.symbol)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(selected ? Color.black : (t == .call ? Color.green : Color.white.opacity(0.55)))
                        .symbolEffect(.bounce, value: selected)
                        .frame(width: model.tabs.count > 6 ? 25 : 28, height: 21)
                        .background {
                            if selected {
                                Capsule().fill(.white).matchedGeometryEffect(id: "pill", in: ns)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(t.title)
            }
        }
        .padding(2.5)
        .background(Capsule().fill(.white.opacity(0.1)))
    }
}

struct StatusCluster: View {
    @ObservedObject var system: SystemMonitor
    @ObservedObject var tools: ToolsModel
    @ObservedObject var focus: FocusMonitor
    var body: some View {
        HStack(spacing: 8) {
            if let f = focus.current {
                Image(systemName: f.symbol).foregroundStyle(f.color)
                    .help("\(f.name) Focus is on")
                    .transition(.scale.combined(with: .opacity))
            }
            if tools.isAwake {
                Image(systemName: "cup.and.saucer.fill").foregroundStyle(.orange)
                    .help("Keep Awake is on")
            }
            if system.micActive && Prefs.bool(Prefs.showMic) {
                Image(systemName: "mic.fill").foregroundStyle(.orange)
                    .help(system.micApp.map { "Microphone in use by \($0)" } ?? "Microphone in use")
            }
            if system.cameraActive && Prefs.bool(Prefs.showCamera) {
                Image(systemName: "video.fill").foregroundStyle(.green)
            }
            if Prefs.bool(Prefs.showBattery), let level = system.batteryLevel {
                HStack(spacing: 3) {
                    Text("\(level)%")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                    Image(systemName: SystemMonitor.batterySymbol(level: level, charging: system.isCharging))
                        .foregroundStyle(system.isCharging ? .green : (level <= 20 ? .red : .white.opacity(0.85)))
                }
            }
        }
        .font(.system(size: 12, weight: .semibold))
    }
}

// MARK: Home

private struct HomeTab: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var music: MusicController
    @ObservedObject var calendar: CalendarModel
    @ObservedObject var weather: WeatherModel
    @ObservedObject private var updater = Updater.shared
    @AppStorage(Prefs.showBuddy) private var showBuddy = true
    @AppStorage(Prefs.showCalendar) private var showCalendar = true
    @AppStorage(Prefs.showWeather) private var showWeather = true

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            if showBuddy {
                BuddyView(mood: mood, accent: music.accent, size: 60)
                    .frame(width: 70, height: 68)
            }
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                VStack(alignment: .leading, spacing: 0) {
                    Text(ctx.date, format: .dateTime.hour().minute())
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(ctx.date, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                    if showWeather, let t = weather.temperature {
                        HStack(spacing: 5) {
                            Image(systemName: weather.symbol)
                                .symbolRenderingMode(.multicolor)
                            Text("\(Int(t.rounded()))°")
                                .foregroundStyle(.white)
                            if let h = weather.high, let l = weather.low {
                                Text("H:\(Int(h.rounded()))° L:\(Int(l.rounded()))°")
                                    .foregroundStyle(.white.opacity(0.45))
                            }
                        }
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .padding(.top, 3)
                        .help("\(weather.summary) in \(weather.city)")
                    }
                }
            }
            Spacer(minLength: 6)
            VStack(spacing: 6) {
                if updater.state == .available, let v = updater.latestVersion {
                Button { AppDelegate.shared.openSettings(pane: "updates") } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.app.fill").foregroundStyle(.blue)
                        Text("Aries \(v) is available").foregroundStyle(.white)
                        Spacer()
                        Text("Update").foregroundStyle(.blue)
                    }
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.blue.opacity(0.15)))
                }
                .buttonStyle(.plain)
            }
            ForEach(model.live.activities.suffix(2)) { a in
                LiveActivityCard(activity: a) { model.live.end(a.id) }
            }
            if showCalendar { eventCard }
                if model.notes.openCount > 0, Prefs.bool(Prefs.showNotesTab) {
                    Button { model.select(.notes) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "checklist").foregroundStyle(.yellow)
                            Text("\(model.notes.openCount) to-do\(model.notes.openCount == 1 ? "" : "s")")
                                .foregroundStyle(.white.opacity(0.8))
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.3))
                        }
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.07)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 210)
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
    }

    private var mood: BuddyView.Mood {
        let hour = Calendar.current.component(.hour, from: Date())
        if music.isPlaying { return .vibing }
        if let b = model.system.batteryLevel, b <= 15, !model.system.isCharging { return .low }
        if hour < 6 { return .sleepy }
        return .happy
    }

    @ViewBuilder private var eventCard: some View {
        Group {
            if !calendar.authorized {
                HStack(spacing: 8) {
                    Image(systemName: "calendar").foregroundStyle(.red)
                    if calendar.statusDenied {
                        Text("Allow Calendars in System Settings")
                            .foregroundStyle(.white.opacity(0.45))
                    } else {
                        Button("Show my next event") { calendar.requestAccess() }
                            .buttonStyle(.plain)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
            } else if let e = calendar.next {
                TimelineView(.periodic(from: .now, by: 30)) { ctx in
                    HStack(alignment: .top, spacing: 8) {
                        Capsule().fill(e.color).frame(width: 4)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(e.title)
                                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text(e.start <= ctx.date ? "Now · until \(e.end.formatted(date: .omitted, time: .shortened))"
                                                     : "\(CalendarModel.relative(e.start, now: ctx.date)) · \(e.start.formatted(date: .omitted, time: .shortened))")
                                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                        Spacer(minLength: 0)
                        if let url = e.joinURL {
                            Button { NSWorkspace.shared.open(url) } label: {
                                Text("Join")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(.black)
                                    .padding(.horizontal, 10).padding(.vertical, 4)
                                    .background(Capsule().fill(.green))
                            }
                            .buttonStyle(PressableStyle(hoverFill: .clear))
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles").foregroundStyle(.yellow)
                    Text("No more events today")
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.07)))
    }
}

// MARK: Shelf

private struct ShelfTab: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var shelf: ShelfStore

    var body: some View {
        HStack(spacing: 12) {
            if shelf.items.isEmpty {
                dropZone
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(shelf.items, id: \.self) { url in
                            ShelfTile(url: url, shelf: shelf)
                                .transition(.scale(scale: 0.4).combined(with: .opacity))
                        }
                        if model.dropTargeted {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                                .foregroundStyle(.white.opacity(0.5))
                                .frame(width: 72, height: 84)
                                .overlay(Image(systemName: "plus").foregroundStyle(.white.opacity(0.7)))
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .padding(.vertical, 4)
                    .animation(.spring(response: 0.4, dampingFraction: 0.65), value: shelf.items)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: model.dropTargeted)
                }
                VStack(spacing: 8) {
                    pill("AirDrop", "airplayaudio") { shelf.airDrop() }
                    pill("Clear", "trash") { withAnimation(.spring) { shelf.clear() } }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }

    private var dropZone: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            .foregroundStyle(.white.opacity(model.dropTargeted ? 0.8 : 0.25))
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.white.opacity(model.dropTargeted ? 0.1 : 0.03)))
            .overlay {
                HStack(spacing: 10) {
                    Image(systemName: model.dropTargeted ? "tray.and.arrow.down.fill" : "tray")
                        .font(.system(size: 22, weight: .semibold))
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.bounce, options: .repeat(3), value: model.dropTargeted)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.dropTargeted ? "Let go to drop it in" : "Drop files on the notch")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                        Text("Keep them here, drag them out anywhere, or AirDrop them")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .foregroundStyle(.white.opacity(0.85))
            }
            .frame(height: 86)
            .scaleEffect(model.dropTargeted ? 1.02 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: model.dropTargeted)
    }

    private func pill(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 86, height: 26)
                .background(Capsule().fill(.white.opacity(0.12)))
        }
        .buttonStyle(PressableStyle(hoverFill: .clear))
    }
}

private struct ShelfTile: View {
    let url: URL
    @ObservedObject var shelf: ShelfStore
    @ViewState private var hover = false

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: ShelfStore.icon(for: url))
                .resizable()
                .frame(width: 42, height: 42)
                .scaleEffect(hover ? 1.08 : 1)
            Text(url.lastPathComponent)
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 66)
        }
        .frame(width: 72, height: 84)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(hover ? 0.12 : 0.05)))
        .overlay(alignment: .topTrailing) {
            if hover {
                Button { withAnimation(.spring) { shelf.remove(url) } } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.white, .gray.opacity(0.8))
                }
                .buttonStyle(.plain)
                .offset(x: 3, y: -3)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: hover)
        .onHover { hover = $0 }
        .onTapGesture(count: 2) { shelf.open(url) }
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .contextMenu {
            Button("Open") { shelf.open(url) }
            Button("Show in Finder") { shelf.reveal(url) }
            Button("AirDrop") { shelf.airDrop([url]) }
            Divider()
            Button("Remove from Shelf") { shelf.remove(url) }
        }
        .help(url.path)
    }
}

// MARK: Timer

private struct TimerTab: View {
    @ObservedObject var timer: TimerModel
    @ObservedObject var focus: FocusModel
    @AppStorage(Prefs.lastTimerMinutes) private var custom = 10.0
    private let presets: [Double] = [1, 5, 10, 15, 30, 60]

    var body: some View {
        Group {
            if timer.isActive { running }
            else if focus.stopwatchActive { stopwatch }
            else { picker }
        }
        .padding(.horizontal, 22)
        .padding(.top, 10)
        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: timer.isActive)
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ForEach(presets, id: \.self) { m in
                    Button { timer.start(minutes: m) } label: {
                        Text(m >= 60 ? "1 hr" : "\(Int(m))m")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity)
                            .frame(height: 28)
                            .background(Capsule().fill(.orange.opacity(0.16)))
                    }
                    .buttonStyle(PressableStyle(hoverFill: .clear))
                }
                Button { focus.startFocus(timer) } label: {
                    Label("Focus", systemImage: "brain.head.profile")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.purple)
                        .padding(.horizontal, 10).frame(height: 28)
                        .background(Capsule().fill(.purple.opacity(0.18)))
                }
                .buttonStyle(PressableStyle(hoverFill: .clear))
                .help("25 min focus, 5 min break, repeating")
                Button { focus.toggleStopwatch() } label: {
                    Image(systemName: "stopwatch.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.yellow)
                        .frame(width: 34, height: 28)
                        .background(Capsule().fill(.yellow.opacity(0.16)))
                }
                .buttonStyle(PressableStyle(hoverFill: .clear))
                .help("Stopwatch")
            }
            HStack(spacing: 10) {
                Image(systemName: "timer").font(.system(size: 18, weight: .semibold)).foregroundStyle(.orange)
                Button { custom = max(1, custom - 1) } label: { Image(systemName: "minus") }
                    .buttonStyle(PressableStyle())
                Text("\(Int(custom)) min")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy, value: custom)
                    .frame(minWidth: 70)
                Button { custom = min(180, custom + 1) } label: { Image(systemName: "plus") }
                    .buttonStyle(PressableStyle())
                Spacer()
                Toggle(isOn: Binding(get: { Prefs.bool(Prefs.timerPausesMusic) },
                                     set: { UserDefaults.standard.set($0, forKey: Prefs.timerPausesMusic) })) {
                    Text("Sleep timer").font(.system(size: 11, weight: .semibold, design: .rounded))
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(.orange)
                .help("Pause music when the timer ends")
                Button { timer.start(minutes: custom) } label: {
                    Label("Start", systemImage: "play.fill")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 16).padding(.vertical, 7)
                        .background(Capsule().fill(.orange))
                }
                .buttonStyle(PressableStyle(hoverFill: .clear))
            }
            .foregroundStyle(.white)
        }
    }

    private var running: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
            HStack(spacing: 18) {
                ZStack {
                    Circle().stroke(.orange.opacity(0.2), lineWidth: 6)
                    Circle().trim(from: 0, to: 1 - timer.progress(at: ctx.date))
                        .stroke(.orange, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.25), value: ctx.date)
                    Image(systemName: timer.isRunning ? "timer" : "pause.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.orange)
                        .symbolEffect(.pulse, isActive: !timer.isRunning)
                }
                .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 0) {
                    Text(TimerModel.format(timer.remaining(at: ctx.date)))
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.snappy, value: Int(timer.remaining(at: ctx.date)))
                    Text(focus.phase == .focus ? "Focus · round \(focus.round)" :
                         focus.phase == .rest ? "Break · round \(focus.round)" :
                         timer.isRunning ? "Ends at \((Date().addingTimeInterval(timer.remaining())).formatted(date: .omitted, time: .shortened))"
                                         : "Paused")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                HStack(spacing: 10) {
                    circleButton("plus", "+1 min", .white.opacity(0.14), .white) { timer.addMinute() }
                    circleButton(timer.isRunning ? "pause.fill" : "play.fill", timer.isRunning ? "Pause" : "Resume",
                                 .orange.opacity(0.22), .orange) {
                        timer.isRunning ? timer.pause() : timer.resume()
                    }
                    circleButton("xmark", "Stop", .white.opacity(0.14), .white) {
                        if focus.phase != .off { focus.stopFocus(timer) } else { timer.stop() }
                    }
                }
            }
        }
    }

    private var stopwatch: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !focus.stopwatchRunning)) { ctx in
            HStack(spacing: 18) {
                Image(systemName: "stopwatch.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.yellow)
                    .symbolEffect(.pulse, isActive: focus.stopwatchRunning)
                    .frame(width: 64, height: 64)
                Text(FocusModel.format(focus.stopwatchElapsed(at: ctx.date)))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                Spacer()
                circleButton(focus.stopwatchRunning ? "pause.fill" : "play.fill", focus.stopwatchRunning ? "Pause" : "Resume",
                             .yellow.opacity(0.22), .yellow) { focus.toggleStopwatch() }
                circleButton("arrow.counterclockwise", "Reset", .white.opacity(0.14), .white) { focus.resetStopwatch() }
            }
        }
    }

    private func circleButton(_ icon: String, _ help: String, _ bg: Color, _ fg: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(fg)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 40, height: 40)
                .background(Circle().fill(bg))
        }
        .buttonStyle(PressableStyle(hoverFill: .clear))
        .help(help)
    }
}

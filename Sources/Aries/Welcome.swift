import AppKit
import SwiftUI
import CoreText
import ServiceManagement

final class WelcomeWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    func closeWindow() { window.orderOut(nil) }
    private let onFinish: () -> Void

    init(app: AppDelegate, onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 920, height: 620),
                          styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init()
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        window.delegate = self
        window.contentView = NSHostingView(rootView: WelcomeFlow(model: app.model, music: app.music) { [weak self] in
            self?.window.close()
        })
        window.center()
    }

    func show() { window.presentInFront() }

    func windowWillClose(_ notification: Notification) { onFinish() }
}

// MARK: - Cursive "hello"-style lettering

/// Turns text into glyph outlines so it can be "written" with a stroke animation.
struct LetteringShape: Shape, @unchecked Sendable {
    let cgPath: CGPath

    init(_ text: String, font: String = "SnellRoundhand-Bold", size: CGFloat = 140) {
        cgPath = Self.outline(text, font: font, size: size)
    }

    func path(in rect: CGRect) -> Path {
        let b = cgPath.boundingBoxOfPath
        guard b.width > 0, b.height > 0 else { return Path() }
        let scale = min(rect.width / b.width, rect.height / b.height)
        var t = CGAffineTransform(translationX: rect.midX, y: rect.midY)
            .scaledBy(x: scale, y: -scale)
            .translatedBy(x: -b.midX, y: -b.midY)
        return Path(cgPath.copy(using: &t) ?? cgPath)
    }

    static func outline(_ text: String, font name: String, size: CGFloat) -> CGPath {
        let font = CTFontCreateWithName(name as CFString, size, nil)
        let attr = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        let line = CTLineCreateWithAttributedString(attr)
        let out = CGMutablePath()
        for run in (CTLineGetGlyphRuns(line) as? [CTRun]) ?? [] {
            let attrs = CTRunGetAttributes(run) as NSDictionary
            let runFont = attrs[kCTFontAttributeName as String].map { $0 as! CTFont } ?? font
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
            for i in 0..<count {
                if let g = CTFontCreatePathForGlyph(runFont, glyphs[i], nil) {
                    out.addPath(g, transform: CGAffineTransform(translationX: positions[i].x, y: positions[i].y))
                }
            }
        }
        return out
    }
}

struct WelcomeLettering: View {
    var text = "Welcome to Aries"
    var duration = 3.8
    var onDone: (() -> Void)? = nil
    @ViewState private var progress: CGFloat = 0
    @ViewState private var filled = false
    @ViewState private var shine: CGFloat = -0.3

    private var shape: LetteringShape { LetteringShape(text) }
    private let gradient = LinearGradient(colors: [Color(red: 1, green: 0.62, blue: 0.75), .white,
                                                   Color(red: 0.75, green: 0.7, blue: 1), Color(red: 0.6, green: 0.85, blue: 1)],
                                          startPoint: .leading, endPoint: .trailing)

    var body: some View {
        ZStack {
            shape
                .trim(from: 0, to: progress)
                .stroke(gradient, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                .opacity(filled ? 0 : 1)
            shape
                .fill(gradient)
                .opacity(filled ? 1 : 0)
                .overlay {
                    // A soft glint sweeping across once the writing finishes.
                    GeometryReader { g in
                        LinearGradient(colors: [.clear, .white.opacity(0.85), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: g.size.width * 0.25)
                            .offset(x: g.size.width * shine)
                            .blendMode(.plusLighter)
                    }
                    .mask(shape)
                }
                .shadow(color: .white.opacity(filled ? 0.35 : 0), radius: 18)
        }
        .onAppear {
            progress = 0; filled = false
            withAnimation(.easeInOut(duration: duration)) { progress = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + duration * 0.92) {
                withAnimation(.easeInOut(duration: 0.8)) { filled = true }
                withAnimation(.easeInOut(duration: 1.4).delay(0.5)) { shine = 1.2 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { onDone?() }
            }
        }
    }
}

/// Drifting colourful glow, used behind the welcome flow.
struct GlowBackground: View {
    var colors: [Color] = [Color(red: 0.98, green: 0.36, blue: 0.55), Color(red: 0.55, green: 0.32, blue: 0.98),
                           Color(red: 0.16, green: 0.62, blue: 0.98), Color(red: 1, green: 0.6, blue: 0.3)]
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: A11y.reduceMotion)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            GeometryReader { g in
                ZStack {
                    Color.black
                    ForEach(0..<colors.count, id: \.self) { i in
                        let d = Double(i)
                        Circle()
                            .fill(RadialGradient(colors: [colors[i], colors[i].opacity(0)], center: .center,
                                                 startRadius: 0, endRadius: g.size.width * 0.32))
                            .frame(width: g.size.width * 0.64)
                            .offset(x: cos(t * (0.13 + d * 0.04) + d * 1.7) * g.size.width * 0.3,
                                    y: sin(t * (0.11 + d * 0.05) + d * 2.3) * g.size.height * 0.3)
                            .opacity(0.55)
                    }
                }
                .blur(radius: 40)
                .frame(width: g.size.width, height: g.size.height)
            }
        }
        .overlay(Color.black.opacity(0.35))
        .ignoresSafeArea()
    }
}

// MARK: - Flow

private enum WelcomeStep: Int, CaseIterable { case hello, features, music, personalize, done }

struct WelcomeFlow: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var music: MusicController
    var finish: () -> Void
    var startAt = 0

    @ViewState private var step: WelcomeStep = .hello
    @ViewState private var helloDone = false

    var body: some View {
        ZStack {
            GlowBackground()
            if step == .hello {
                BrandIntroPlayer { helloDone = true }
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
            VStack(spacing: 0) {
                ZStack {
                    switch step {
                    case .hello: hello.transition(.opacity.combined(with: .scale(scale: 1.05)))
                    case .features: FeaturesPage().transition(page)
                    case .music: MusicSetupPage(music: music).transition(page)
                    case .personalize: PersonalizePage(model: model).transition(page)
                    case .done: DonePage().transition(page)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if step != .hello { footer.transition(.opacity) }
            }
            .padding(40)
        }
        .environment(\.colorScheme, .dark)
        .frame(minWidth: 860, minHeight: 580)
        .onAppear { if startAt > 0 { step = WelcomeStep(rawValue: startAt) ?? .hello } }
    }

    private var page: AnyTransition {
        .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity))
    }

    /// The brand intro plays full-bleed, then "Get Started" rises in above the sign-off.
    private var hello: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("Your notch, alive.")
                .font(.system(size: 19, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
            Button { go(.features) } label: {
                Text("Get Started")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 30).padding(.vertical, 12)
                    .background(Capsule().fill(.white))
            }
            .buttonStyle(PressableStyle(hoverFill: .clear))
            .keyboardShortcut(.defaultAction)
        }
        .padding(.bottom, 56)
        .opacity(helloDone ? 1 : 0)
        .offset(y: helloDone ? 0 : 16)
        .animation(.spring(response: 0.7, dampingFraction: 0.8), value: helloDone)
    }

    private var footer: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(WelcomeStep.allCases.dropFirst(), id: \.self) { s in
                    Capsule()
                        .fill(.white.opacity(s == step ? 0.9 : 0.25))
                        .frame(width: s == step ? 22 : 7, height: 7)
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: step)
            Spacer()
            if step != .done && step != .features {
                Button("Back") { go(WelcomeStep(rawValue: step.rawValue - 1)!) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.trailing, 12)
            }
            Button {
                if step == .done { finish() } else { go(WelcomeStep(rawValue: step.rawValue + 1)!) }
            } label: {
                Text(step == .done ? "Start using Aries" : "Continue")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 24).padding(.vertical, 10)
                    .background(Capsule().fill(.white))
            }
            .buttonStyle(PressableStyle(hoverFill: .clear))
            .keyboardShortcut(.defaultAction)
        }
    }

    private func go(_ s: WelcomeStep) {
        withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) { step = s }
    }
}

private struct PageTitle: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(spacing: 8) {
            Text(title).font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(.white)
            Text(subtitle).font(.system(size: 15, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
    }
}

private struct FeaturesPage: View {
    @ViewState private var shown = false
    private let items: [(String, Color, String, String)] = [
        ("music.note", .pink, "Live music", "Spotify & Apple Music in your notch"),
        ("quote.bubble.fill", .purple, "Synced lyrics", "Full-screen, word by word"),
        ("iphone", .green, "Your iPhone too", "See & control phone playback"),
        ("phone.fill", .green, "Calls", "Timer, mute and answer"),
        ("note.text", .yellow, "Notes", "Quick to-dos with ⌥⌘N"),
        ("tray.full.fill", .cyan, "Shelf", "Drop files on the notch"),
        ("timer", .orange, "Timers", "Countdown right in the notch"),
        ("calendar", .red, "Your day", "Next event, weather, battery"),
    ]

    var body: some View {
        VStack(spacing: 30) {
            PageTitle(title: "Meet your island", subtitle: "Hover the notch any time. Everything lives right there.")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), spacing: 14) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: item.0)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(item.1)
                            .frame(width: 44, height: 44)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(item.1.opacity(0.18)))
                        Text(item.2).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(.white)
                        Text(item.3).font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.55))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.white.opacity(0.08)))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.08)))
                    .opacity(shown ? 1 : 0)
                    .offset(y: shown ? 0 : 24)
                    .animation(.spring(response: 0.6, dampingFraction: 0.75).delay(Double(i) * 0.06), value: shown)
                }
            }
        }
        .onAppear { shown = true }
    }
}

private struct MusicSetupPage: View {
    @ObservedObject var music: MusicController
    @AppStorage(Prefs.preferredSource) private var preferredSource = "auto"
    @ViewState private var accessStatus = ""

    var body: some View {
        VStack(spacing: 26) {
            PageTitle(title: "Your music, front and center",
                      subtitle: "Aries is built around Spotify, and works great with Apple Music too.")
            VStack(spacing: 12) {
                row("hand.raised.fill", .blue, "Let Aries see what's playing",
                    "macOS will ask to let Aries control Spotify and Music. Click OK.") {
                    Button(accessStatus.isEmpty ? "Allow" : accessStatus) { requestAutomation() }
                        .buttonStyle(.borderedProminent)
                }
                row("iphone", .green, "Music on your iPhone",
                    "Connect Spotify once to see and control what's playing on your phone, speakers or any device.") {
                    Button("Set Up…") { AppDelegate.shared.openSettings() }.buttonStyle(.bordered)
                }
                row("star.fill", .yellow, "Preferred player", "Which one wins when both are playing.") {
                    Picker("", selection: $preferredSource) {
                        Text("Auto").tag("auto"); Text("Spotify").tag("spotify"); Text("Music").tag("music")
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 220)
                }
            }
            .frame(maxWidth: 640)
        }
    }

    private func requestAutomation() {
        accessStatus = "Asking…"
        LocalPlayers.queue.async {
            var asked = false
            for (id, name) in [(LocalPlayers.spotifyID, "Spotify"), (LocalPlayers.musicID, "Music")] where LocalPlayers.isRunning(id) {
                LocalPlayers.run("tell application \"\(name)\" to get player state")
                asked = true
            }
            DispatchQueue.main.async {
                accessStatus = asked ? "Done ✓" : "Open Spotify, then tap again"
                music.pollLocal()
            }
        }
    }
}

private struct PersonalizePage: View {
    @ObservedObject var model: IslandModel
    @ViewState private var city = Prefs.string(Prefs.weatherCity)
    @ViewState private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @AppStorage(Prefs.hotkeys) private var hotkeys = true

    var body: some View {
        VStack(spacing: 26) {
            PageTitle(title: "Make it yours", subtitle: "All optional. You can change these any time in Settings.")
            VStack(spacing: 12) {
                row("cloud.sun.fill", .cyan, "Weather", model.weather.city.isEmpty ? "Type your city" : model.weather.city) {
                    HStack {
                        TextField("City", text: $city).textFieldStyle(.roundedBorder).frame(width: 150)
                            .onSubmit { model.weather.setCity(city) }
                        Button("Set") { model.weather.setCity(city) }
                    }
                }
                row("calendar", .red, "Calendar", "Your next event and a heads-up before meetings.") {
                    Button(model.calendar.authorized ? "Allowed ✓" : "Allow") { model.calendar.requestAccess() }
                        .disabled(model.calendar.authorized)
                }
                row("phone.arrow.down.left.fill", .green, "Answer calls from the notch",
                    "Needs Accessibility so Aries can press Accept/Decline on the call banner.") {
                    Button(model.calls.axTrusted ? "Allowed ✓" : "Allow") { model.calls.requestAccessibility() }
                        .disabled(model.calls.axTrusted)
                }
                row("keyboard", .purple, "Keyboard shortcuts", "⌥⌘I island · ⌥⌘P play · ⌥⌘N note · ⌥⌘M mute") {
                    Toggle("", isOn: $hotkeys).toggleStyle(.switch).labelsHidden()
                }
                row("power", .orange, "Open at login", "Have Aries ready every time you start your Mac.") {
                    Toggle("", isOn: $launchAtLogin).toggleStyle(.switch).labelsHidden()
                        .onChange(of: launchAtLogin) { _, on in
                            _ = try? (on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister())
                        }
                }
            }
            .frame(maxWidth: 640)
        }
    }
}

private struct DonePage: View {
    @ViewState private var circle: CGFloat = 0
    @ViewState private var check: CGFloat = 0
    @ViewState private var text = false

    var body: some View {
        VStack(spacing: 26) {
            ZStack {
                Circle()
                    .trim(from: 0, to: circle)
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Path { p in
                    p.move(to: CGPoint(x: 38, y: 64))
                    p.addLine(to: CGPoint(x: 56, y: 82))
                    p.addLine(to: CGPoint(x: 88, y: 44))
                }
                .trim(from: 0, to: check)
                .stroke(Color.green, style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                .frame(width: 126, height: 126)
            }
            .frame(width: 126, height: 126)
            .shadow(color: .green.opacity(0.5), radius: circle == 1 ? 22 : 0)
            .scaleEffect(check == 1 ? 1 : 0.92)

            VStack(spacing: 10) {
                Text("You're all set!")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Move your pointer up to the notch to open Aries.\nRight-click it any time for Settings.")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
            .opacity(text ? 1 : 0)
            .offset(y: text ? 0 : 12)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) { circle = 1 }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.55).delay(0.5)) { check = 1 }
            withAnimation(.easeOut(duration: 0.5).delay(0.8)) { text = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            }
        }
    }
}

private func row<C: View>(_ icon: String, _ color: Color, _ title: String, _ subtitle: String,
                          @ViewBuilder trailing: () -> C) -> some View {
    HStack(spacing: 14) {
        Image(systemName: icon)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 40, height: 40)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(color.opacity(0.18)))
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(.white)
            Text(subtitle).font(.system(size: 12.5, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
        Spacer()
        trailing()
    }
    .padding(14)
    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(0.08)))
}

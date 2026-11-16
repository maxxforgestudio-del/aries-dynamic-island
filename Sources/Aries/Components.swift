import SwiftUI
import AppKit

/// The notch silhouette: concave "ears" that melt into the menu bar at the top,
/// and soft continuous corners at the bottom.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in r: CGRect) -> Path {
        let t = min(topRadius, r.width / 4)
        let b = min(bottomRadius, (r.width - 2 * t) / 2, r.height - t)
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addCurve(to: CGPoint(x: r.minX + t, y: r.minY + t),
                   control1: CGPoint(x: r.minX + t * 0.62, y: r.minY),
                   control2: CGPoint(x: r.minX + t, y: r.minY + t * 0.38))
        p.addLine(to: CGPoint(x: r.minX + t, y: r.maxY - b))
        p.addCurve(to: CGPoint(x: r.minX + t + b, y: r.maxY),
                   control1: CGPoint(x: r.minX + t, y: r.maxY - b * 0.45),
                   control2: CGPoint(x: r.minX + t + b * 0.45, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - t - b, y: r.maxY))
        p.addCurve(to: CGPoint(x: r.maxX - t, y: r.maxY - b),
                   control1: CGPoint(x: r.maxX - t - b * 0.45, y: r.maxY),
                   control2: CGPoint(x: r.maxX - t, y: r.maxY - b * 0.45))
        p.addLine(to: CGPoint(x: r.maxX - t, y: r.minY + t))
        p.addCurve(to: CGPoint(x: r.maxX, y: r.minY),
                   control1: CGPoint(x: r.maxX - t, y: r.minY + t * 0.38),
                   control2: CGPoint(x: r.maxX - t * 0.62, y: r.minY))
        p.closeSubpath()
        return p
    }
}

struct ArtworkView: View {
    var image: NSImage?
    var size: CGFloat
    var radius: CGFloat
    var accent: Color = .white

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            } else {
                LinearGradient(colors: [accent.opacity(0.55), accent.opacity(0.18)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
            .strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
        .animation(.easeInOut(duration: 0.35), value: image)
    }
}

/// Playful live bars. (Real audio levels would need screen-recording permission;
/// this stays lightweight and pauses when playback pauses.)
struct VisualizerView: View {
    var isPlaying: Bool
    var color: Color
    var bars = 4
    var height: CGFloat = 14

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !isPlaying || A11y.reduceMotion)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2.2) {
                ForEach(0..<bars, id: \.self) { i in
                    Capsule()
                        .fill(color.gradient)
                        .frame(width: 3, height: max(3, (isPlaying ? level(i, t) : 0.2) * height))
                }
            }
            .frame(height: height)
        }
        .animation(.easeOut(duration: 0.25), value: isPlaying)
    }

    private func level(_ i: Int, _ t: Double) -> CGFloat {
        let d = Double(i)
        let a = sin(t * (6.1 + d * 1.9) + d * 1.3)
        let b = sin(t * (2.3 + d * 0.7) + d * 2.1)
        let c = sin(t * (11.0 - d * 1.4) + d)
        return CGFloat(0.28 + 0.72 * abs(a * 0.5 + b * 0.3 + c * 0.2))
    }
}

struct PressableStyle: ButtonStyle {
    var hoverFill: Color = .white.opacity(0.12)
    func makeBody(configuration: Configuration) -> some View {
        PressableBody(configuration: configuration, hoverFill: hoverFill)
    }
    private struct PressableBody: View {
        let configuration: Configuration
        let hoverFill: Color
        @ViewState private var hover = false
        var body: some View {
            configuration.label
                .padding(6)
                .background(Circle().fill(hover ? hoverFill : .clear))
                .scaleEffect(configuration.isPressed ? 0.86 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.15), value: hover)
                .onHover { hover = $0 }
                .contentShape(Circle())
        }
    }
}

struct ScrubberView: View {
    @ObservedObject var music: MusicController
    var tint: Color
    var barHeight: CGFloat = 5
    var font: Font = .system(size: 10.5, weight: .medium, design: .rounded)
    var timeColor: Color = .white.opacity(0.55)
    var timesBelow = false

    @ViewState private var drag: Double?
    @ViewState private var hover = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            let dur = max(music.duration, 1)
            let pos = min(dur, max(0, drag ?? music.position))
            if timesBelow {
                VStack(spacing: 6) {
                    bar(pos: pos, dur: dur)
                    HStack {
                        Text(fmt(pos)); Spacer(); Text("-" + fmt(dur - pos))
                    }
                    .font(font).foregroundStyle(timeColor).monospacedDigit()
                }
            } else {
                HStack(spacing: 10) {
                    Text(fmt(pos)).frame(width: 34, alignment: .trailing)
                    bar(pos: pos, dur: dur)
                    Text("-" + fmt(dur - pos)).frame(width: 38, alignment: .leading)
                }
                .font(font).foregroundStyle(timeColor).monospacedDigit()
            }
        }
    }

    private func bar(pos: Double, dur: Double) -> some View {
        GeometryReader { geo in
            let active = drag != nil || hover
            let h = active ? barHeight * 1.7 : barHeight
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.16))
                Capsule().fill(tint)
                    .frame(width: max(h, geo.size.width * pos / dur))
            }
            .frame(height: h)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onHover { hover = $0 }
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    drag = Double(min(max(0, v.location.x / geo.size.width), 1)) * dur
                }
                .onEnded { _ in
                    if let d = drag { music.seek(to: d) }
                    drag = nil
                })
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: active)
        }
        .frame(height: 16)
    }

    private func fmt(_ s: Double) -> String {
        guard s.isFinite else { return "0:00" }
        let t = Int(s.rounded(.down))
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}

extension View {
    /// Liquid Glass on macOS 26+, frosted material before that.
    @ViewBuilder func glassCapsule(tint: Color? = nil) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(tint.map { .regular.tint($0).interactive() } ?? .regular.interactive(), in: .capsule)
        } else {
            self.background(.ultraThinMaterial, in: Capsule())
        }
    }

    @ViewBuilder func glassCircle() -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: .circle)
        } else {
            self.background(.ultraThinMaterial, in: Circle())
        }
    }
}

/// Same as SwiftUI's `@State`. The Command Line Tools ship without the SwiftUI
/// macro plugin that `@State` now needs, so we wrap `State` directly.
@propertyWrapper
struct ViewState<Value>: DynamicProperty {
    private var storage: State<Value>
    init(wrappedValue: Value) { storage = State(initialValue: wrappedValue) }
    var wrappedValue: Value {
        get { storage.wrappedValue }
        nonmutating set { storage.wrappedValue = newValue }
    }
    var projectedValue: Binding<Value> { storage.projectedValue }
}


extension NSWindow {
    /// Reliably brings a window to the front. Agent apps on modern macOS can't always activate
    /// themselves, so the window is lifted above other apps briefly, then settles back.
    func presentInFront(float: Bool = false) {
        if #available(macOS 14.0, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
        NSCursor.setHiddenUntilMouseMoves(true)
        let original = level
        level = .floating
        center()
        orderFrontRegardless()
        makeKey()
        if !float {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.level = original }
        }
    }
}

/// Maxx Forge Studio brand assets and release naming.
enum Brand {
    static let company = "Maxx Forge Studio"
    static let copyright = "© 2026 Maxx Forge Studio. All rights reserved."
    static let codename = Bundle.main.object(forInfoDictionaryKey: "AriesCodename") as? String ?? ""
    static var versionLine: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        return codename.isEmpty ? "Version \(v)" : "Version \(v) “\(codename)”"
    }
    static let appLogo: NSImage? = Bundle.main.url(forResource: "AriesLogo", withExtension: "png")
        .flatMap(NSImage.init(contentsOf:))
        ?? NSImage(contentsOfFile: FileManager.default.currentDirectoryPath + "/Resources/Branding/AriesLogo.png")
    static let logo: NSImage? = Bundle.main.url(forResource: "MaxxForgeStudio", withExtension: "png")
        .flatMap(NSImage.init(contentsOf:))
        ?? NSImage(contentsOfFile: FileManager.default.currentDirectoryPath + "/Resources/Branding/MaxxForgeStudio.png")
}

/// "A Maxx Forge Studio product" mark with the company logo.
struct MadeByMaxxForge: View {
    var compact = false
    var body: some View {
        HStack(spacing: compact ? 6 : 10) {
            if let logo = Brand.logo {
                Image(nsImage: logo).resizable().interpolation(.high).scaledToFit()
                    .frame(width: compact ? 22 : 34, height: compact ? 22 : 34)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(compact ? "A Maxx Forge Studio product" : "A MAXX FORGE STUDIO PRODUCT")
                    .font(.system(size: compact ? 10.5 : 11, weight: .heavy, design: .rounded))
                    .tracking(compact ? 0 : 1.2)
                if !compact {
                    Text(Brand.copyright).font(.system(size: 10, weight: .medium)).opacity(0.6)
                }
            }
        }
    }
}

// MARK: - Accessibility

enum A11y {
    static var reduceMotion: Bool {
        Prefs.bool(Prefs.reduceMotion) || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
    static var reduceTransparency: Bool {
        Prefs.bool(Prefs.reduceTransparency) || NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }
    static var highContrast: Bool {
        Prefs.bool(Prefs.highContrast) || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    }
    static var scale: CGFloat { Prefs.bool(Prefs.largerIsland) ? 1.12 : 1 }

    /// Speaks island updates aloud when VoiceOver is running.
    static func announce(_ text: String) {
        guard Prefs.bool(Prefs.announce), NSWorkspace.shared.isVoiceOverEnabled else { return }
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
}

// MARK: - Aquatic glass

/// Real behind-window blur (what's on your screen shows through, frosted).
struct GlassBackdrop: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow
        v.state = .active
        v.appearance = NSAppearance(named: .darkAqua)
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) { v.material = material }
}

/// The island's surface: solid black where it meets the notch, flowing into
/// frosted "Aquatic" glass below, with a soft light rim and a slow shimmer.
struct IslandSurface: View {
    var shape: NotchShape
    var expanded: Bool
    var notchHeight: CGFloat
    var accent: Color
    @AppStorage(Prefs.islandStyle) private var style = "aquatic"

    var body: some View {
        GeometryReader { g in
            let crystal = style == "crystal" && !A11y.reduceTransparency
            let glass = crystal || (expanded && style == "aquatic" && !A11y.reduceTransparency)
            let solidUntil = min(1, (notchHeight + 6) / max(g.size.height, 1))
            let fadeTo = min(1, (notchHeight + 46) / max(g.size.height, 1))
            ZStack {
                if glass {
                    GlassBackdrop()
                    Color.black.opacity(crystal ? 0.28 : 0.46)
                    LinearGradient(colors: [accent.opacity(0.0), accent.opacity(0.14)], startPoint: .top, endPoint: .bottom)
                    if !crystal {
                        // Aquatic: solid where it meets the notch, so the island blends into the camera.
                        LinearGradient(stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: solidUntil),
                            .init(color: .black.opacity(0), location: fadeTo),
                        ], startPoint: .top, endPoint: .bottom)
                    }
                    if !A11y.reduceMotion { Shimmer() }
                } else {
                    Color.black
                }
            }
            .clipShape(shape)
            .overlay {
                if glass {
                    shape.stroke(LinearGradient(colors: [.white.opacity(0.0), .white.opacity(0.10), .white.opacity(0.32)],
                                                startPoint: .top, endPoint: .bottom), lineWidth: 1)
                }
            }
            .overlay {
                if A11y.highContrast { shape.stroke(.white.opacity(0.55), lineWidth: 1.5) }
            }
            .animation(.easeInOut(duration: 0.35), value: glass)
        }
    }
}

/// A slow diagonal light sweep, like light moving through water.
private struct Shimmer: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            GeometryReader { g in
                let x = (t.truncatingRemainder(dividingBy: 7) / 7) * 1.8 - 0.4
                LinearGradient(colors: [.clear, .white.opacity(0.07), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: g.size.width * 0.35)
                    .rotationEffect(.degrees(18))
                    .offset(x: g.size.width * x - g.size.width * 0.2)
                    .blendMode(.plusLighter)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - iOS-style morphing

private struct IslandNamespaceKey: EnvironmentKey { static let defaultValue: Namespace.ID? = nil }
extension EnvironmentValues {
    var islandNamespace: Namespace.ID? {
        get { self[IslandNamespaceKey.self] }
        set { self[IslandNamespaceKey.self] = newValue }
    }
}

/// Lets the same element (e.g. album art) glide between the closed and open island.
struct IslandMatched: ViewModifier {
    let id: String
    @Environment(\.islandNamespace) private var ns
    func body(content: Content) -> some View {
        if let ns, !A11y.reduceMotion {
            content.matchedGeometryEffect(id: id, in: ns)
        } else {
            content
        }
    }
}

extension View {
    func islandMatched(_ id: String) -> some View { modifier(IslandMatched(id: id)) }
}

/// Blur used by the island's content transitions (content "condenses" in and out, like iOS).
struct BlurTransition: ViewModifier {
    let radius: CGFloat
    func body(content: Content) -> some View { content.blur(radius: radius) }
}

extension AnyTransition {
    static func islandContent(scale: CGFloat = 0.9) -> AnyTransition {
        .modifier(active: BlurTransition(radius: 10), identity: BlurTransition(radius: 0))
            .combined(with: .opacity)
            .combined(with: .scale(scale: scale, anchor: .top))
    }
}

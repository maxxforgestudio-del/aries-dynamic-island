import AppKit
import AVFoundation
import SwiftUI

/// A vertical (9:16) high-energy launch ad for Aries 2.0, in the style of a modern product spot:
/// dark stage, one glowing accent, everything moving on the beat, and the real island morphing
/// in a MacBook notch.  Run: `Aries --render-ad <outDir> <screenshotsDir> [--preview]`
enum Ad {
    static let size = CGSize(width: 1080, height: 1920)
    static let bpm = 128.0
    static var beat: Double { 60 / bpm }
    static let aqua = Color(red: 0.32, green: 0.86, blue: 1.0)

    // Scene start times (seconds)
    static let logo = 0.0, laptop = 2.4, music = 5.2, live = 9.0, lyrics = 12.4, vinyl = 15.4, karaoke = 18.2,
               calls = 21.4, focus = 24.4, widgets = 27.6, tools = 30.8, timers = 33.6, toasts = 36.4, hype = 40.6, end = 44.4
    static let duration = 49.4
    static var cuts: [Double] { [laptop, music, live, lyrics, vinyl, karaoke, calls, focus, widgets, tools, timers, toasts, hype, end] }

    struct Assets {
        var img: [String: NSImage] = [:]
        var widgets: [NSImage] = []
        var art: NSImage?
        var footage: URL?
        /// A frame of the real screen recording (60 fps), by time in the recording.
        func live(_ t: Double) -> NSImage? {
            guard let footage else { return nil }
            let i = max(1, min(1620, Int(t * 60) + 1))
            return NSImage(contentsOf: footage.appendingPathComponent(String(format: "f%05d.jpg", i)))
        }
    }

    @MainActor static func loadAssets(_ shots: URL) -> Assets {
        var a = Assets()
        for n in ["01-compact-music", "02-music", "09-call-incoming", "11-compact-call", "08b-tools", "05-home"] {
            a.img[n] = Trailer.load(shots, n)
        }
        for n in ["15-lyrics", "15e-artist"] { a.img[n] = Trailer.load(shots, n, maxSide: 1400) }
        // Slice the six widgets out of the widget sheet (2× of a 420×780 layout).
        if let sheet = NSImage(contentsOf: shots.appendingPathComponent("15d-widgets.png")),
           let cg = sheet.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let rects = [CGRect(x: 90, y: 105, width: 660, height: 316), CGRect(x: 90, y: 450, width: 316, height: 316),
                         CGRect(x: 434, y: 450, width: 316, height: 316), CGRect(x: 90, y: 795, width: 316, height: 316),
                         CGRect(x: 434, y: 795, width: 316, height: 316), CGRect(x: 90, y: 1140, width: 660, height: 316)]
            a.widgets = rects.compactMap { r in cg.cropping(to: r).map { NSImage(cgImage: $0, size: r.size) } }
        }
        a.art = Snapshotter.demoArtwork()
        let f = shots.deletingLastPathComponent().appendingPathComponent("footage")
        if FileManager.default.fileExists(atPath: f.path) { a.footage = f }
        return a
    }

    @MainActor static func render(outDir: URL, shots: URL) throws {
        let assets = loadAssets(shots)
        let video = outDir.appendingPathComponent("ad-video.mp4")
        try IntroExporter.renderVideo(to: video, size: size, fps: 60, duration: duration, frame: { t, sz in
            let r = ImageRenderer(content: AdView(t: t, a: assets).frame(width: sz.width, height: sz.height))
            r.scale = 1
            r.proposedSize = ProposedViewSize(sz)
            return r.cgImage
        }, progress: { p in print(String(format: "video %.0f%%", p * 100)); fflush(stdout) })
        try AdAudio.render(to: outDir.appendingPathComponent("ad-audio.wav"))
        print("audio done"); fflush(stdout)
    }

    /// 1 right on a beat, decaying fast: drives glow pulses and camera kicks.
    static func pulse(_ t: Double, from start: Double = 2.4) -> Double {
        guard t >= start else { return 0 }
        let phase = (t - start).truncatingRemainder(dividingBy: beat)
        return exp(-phase * 9)
    }
}

// MARK: - Root

struct AdView: View {
    let t: Double
    let a: Ad.Assets

    var body: some View {
        let p = Ad.pulse(t)
        let shake = t > Ad.laptop && t < Ad.end ? p : 0
        ZStack {
            Color(red: 0.01, green: 0.02, blue: 0.05)
            // Stage glow, breathing with the beat
            RadialGradient(colors: [Ad.aqua.opacity(0.28 + 0.18 * p), Color(red: 0.2, green: 0.1, blue: 0.6).opacity(0.15), .clear],
                           center: UnitPoint(x: 0.5, y: 0.48 + 0.04 * sin(t * 0.7)), startRadius: 0, endRadius: 1000)
            Particles(t: t).opacity(0.8)

            Group { scenes }
                .offset(x: 6 * shake * sin(t * 91), y: 8 * shake * cos(t * 77))
                .scaleEffect(1 + 0.012 * shake)

            // Cut flash
            if let c = Ad.cuts.last(where: { $0 <= t }), t - c < 0.35 {
                Ad.aqua.opacity(0.16 * exp(-(t - c) * 14)).blendMode(.plusLighter)
            }
            // Fade to black at the very end
            Color.black.opacity(ramp(t, Ad.duration - 0.7, Ad.duration))
        }
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder private var scenes: some View {
        if t < Ad.laptop + 0.3 { LogoScene(u: t) }
        if t >= Ad.laptop - 0.1 && t < Ad.music + 0.1 { LaptopScene(u: t - Ad.laptop) }
        if t >= Ad.music - 0.1 && t < Ad.lyrics + 0.1 { MusicScene(u: t - Ad.music, a: a) }
        if t >= Ad.live - 0.05 && t < Ad.lyrics + 0.1 { LiveScene(u: t - Ad.live, a: a) }
        if t >= Ad.lyrics - 0.05 && t < Ad.vinyl + 0.1 { LyricsScene(u: t - Ad.lyrics, a: a) }
        if t >= Ad.vinyl - 0.05 && t < Ad.karaoke + 0.1 { VinylScene(u: t - Ad.vinyl, art: a.art) }
        if t >= Ad.karaoke - 0.05 && t < Ad.calls + 0.1 { KaraokeScene(u: t - Ad.karaoke, art: a.art) }
        if t >= Ad.calls - 0.05 && t < Ad.focus + 0.1 { CallsScene(u: t - Ad.calls, a: a) }
        if t >= Ad.focus - 0.05 && t < Ad.widgets + 0.1 { FocusScene(u: t - Ad.focus, a: a) }
        if t >= Ad.widgets - 0.05 && t < Ad.tools + 0.1 { WidgetsScene(u: t - Ad.widgets, a: a) }
        if t >= Ad.tools - 0.05 && t < Ad.timers + 0.1 { ToolsScene(u: t - Ad.tools, a: a) }
        if t >= Ad.timers - 0.05 && t < Ad.toasts + 0.1 { TimersScene(u: t - Ad.timers, a: a) }
        if t >= Ad.toasts - 0.05 && t < Ad.hype + 0.1 { ToastsScene(u: t - Ad.toasts) }
        if t >= Ad.hype - 0.05 && t < Ad.end + 0.1 { HypeScene(u: t - Ad.hype) }
        if t >= Ad.end - 0.05 { AdEndScene(u: t - Ad.end) }
    }
}

// MARK: - Shared pieces

/// Big two-line headline that punches in word by word.
private struct Headline: View {
    let top: String
    var bottom: String? = nil
    let u: Double
    var y: CGFloat = -640
    var size: CGFloat = 96

    var body: some View {
        VStack(spacing: 6) {
            KineticText(text: top, u: u, size: size, weight: .black, gradient: [.white, .white], stagger: 0.06)
            if let bottom {
                KineticText(text: bottom, u: u - 0.25, size: size, weight: .black, gradient: [Ad.aqua, .white], stagger: 0.06)
            }
        }
        .shadow(color: Ad.aqua.opacity(0.35), radius: 24)
        .offset(y: y)
    }
}

/// Scene in/out envelope: quick zoom-in entrance, blur-out exit.
private struct SceneEnvelope: ViewModifier {
    let u: Double
    let len: Double
    func body(content: Content) -> some View {
        let inP = ramp(u, 0, 0.3), out = ramp(u, len - 0.18, len)
        content
            .scaleEffect(0.92 + 0.08 * inP + 0.12 * out)
            .opacity(inP * (1 - out))
            .blur(radius: 18 * out + 8 * (1 - inP))
    }
}

private extension View {
    func envelope(_ u: Double, _ len: Double) -> some View { modifier(SceneEnvelope(u: u, len: len)) }
}

/// The top of a Mac screen, close up, with the island hanging from the notch.
private struct ScreenTop<Content: View>: View {
    let u: Double
    @ViewBuilder var island: Content

    var body: some View {
        ZStack(alignment: .top) {
            // Wallpaper
            RoundedRectangle(cornerRadius: 46, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.08, green: 0.12, blue: 0.3), Color(red: 0.25, green: 0.12, blue: 0.4),
                                              Color(red: 0.05, green: 0.3, blue: 0.45)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 46, style: .continuous).stroke(Color(white: 0.25), lineWidth: 10))
            // Menu bar hints
            HStack {
                HStack(spacing: 14) { ForEach(0..<4, id: \.self) { i in Capsule().fill(.white.opacity(0.35)).frame(width: i == 0 ? 22 : 48, height: 9) } }
                Spacer()
                HStack(spacing: 14) { ForEach(0..<4, id: \.self) { _ in Capsule().fill(.white.opacity(0.35)).frame(width: 30, height: 9) } }
            }
            .padding(.horizontal, 40).padding(.top, 22)
            island
        }
        .frame(width: 1000, height: 760)
        .clipShape(RoundedRectangle(cornerRadius: 46, style: .continuous))
        .shadow(color: Ad.aqua.opacity(0.35), radius: 60)
        .rotation3DEffect(.degrees(8 * sin(u * 0.9)), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
        .rotation3DEffect(.degrees(10), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
    }
}

/// The island itself: square where it meets the bezel, round at the bottom; content fades in once it settles.
private struct IslandBlob: View {
    let w: CGFloat
    let h: CGFloat
    var image: NSImage? = nil
    var contentOpacity: Double = 1
    var glow: Double = 0.5
    var glowColor: Color = Ad.aqua

    var body: some View {
        let r = min(h / 2, 44)
        ZStack(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: r, bottomTrailingRadius: r, topTrailingRadius: 0,
                                   style: .continuous).fill(.black)
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFill()
                    .frame(width: w, height: h, alignment: .top)
                    .opacity(contentOpacity)
            }
        }
        .frame(width: w, height: h)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: r, bottomTrailingRadius: r, topTrailingRadius: 0, style: .continuous))
        .shadow(color: glowColor.opacity(glow), radius: 30)
    }
}

/// Springy interpolation between island sizes.
private func morph(_ u: Double, _ at: Double, _ from: CGFloat, _ to: CGFloat, len: Double = 0.55) -> CGFloat {
    from + (to - from) * CGFloat(pop(u, at, len))
}

private func aspectH(_ img: NSImage?, _ w: CGFloat, fallback: CGFloat) -> CGFloat {
    guard let img, img.size.width > 0 else { return fallback }
    return w * img.size.height / img.size.width
}

// MARK: - Real footage

/// A frame of the real screen recording, presented like a hero shot with a "recorded live" tag.
private struct LiveFrame: View {
    let image: NSImage?
    let u: Double
    var tint: Color = Ad.aqua

    var body: some View {
        let enter = ramp(u, 0, 0.45)
        VStack(spacing: 22) {
            ZStack {
                if let image {
                    Image(nsImage: image).resizable().interpolation(.high).scaledToFill()
                        .frame(width: 1020, height: 382, alignment: .top)
                }
            }
            .frame(width: 1020, height: 382)
            .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 34, style: .continuous)
                .stroke(LinearGradient(colors: [.white.opacity(0.6), tint.opacity(0.5), .white.opacity(0.1)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2.5))
            .shadow(color: tint.opacity(0.55), radius: 60)
            .shadow(color: .black.opacity(0.6), radius: 30, y: 20)
            .rotation3DEffect(.degrees(16 * (1 - enter) + 3 * sin(u * 1.1)), axis: (x: 1, y: 0.2, z: 0), perspective: 0.5)
            .scaleEffect(0.88 + 0.12 * enter + 0.02 * u)
            HStack(spacing: 10) {
                Circle().fill(.red).frame(width: 14, height: 14)
                    .opacity(0.5 + 0.5 * sin(u * 8))
                Text("RECORDED LIVE ON MACBOOK AIR").font(.system(size: 24, weight: .bold)).tracking(4)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .opacity(ramp(u, 0.3, 0.6))
        }
    }
}

private struct LiveScene: View {
    let u: Double
    let a: Ad.Assets
    var body: some View {
        let len = Ad.lyrics - Ad.live
        ZStack {
            Headline(top: "Live Activities.", bottom: "Right in the notch.", u: u - 0.1, y: -640, size: 86)
            LiveFrame(image: a.live(3.9 + u), u: u, tint: .orange).offset(y: 40)
            Text("Deliveries · rides · timers · scores · anything")
                .font(.system(size: 32, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                .offset(y: 520).opacity(ramp(u, 0.8, 1.2))
        }
        .envelope(u, len)
    }
}

/// Quick cuts of real alerts, one per beat.
private struct FocusScene: View {
    let u: Double
    let a: Ad.Assets
    var body: some View {
        let len = Ad.widgets - Ad.focus
        let clips: [(Double, String, Color)] = [(1.0, "Knows your Focus.", .indigo), (19.9, "Caps Lock.", .green),
                                                (22.0, "AirPods.", .white), (1.6, "Do Not Disturb.", .indigo)]
        let seg = len / Double(clips.count)
        let i = min(clips.count - 1, Int(u / seg))
        let local = u - Double(i) * seg
        let c = clips[i]
        ZStack {
            KineticText(text: c.1, u: local, size: 100, weight: .black, gradient: [.white, c.2 == .white ? Ad.aqua : c.2], stagger: 0.05)
                .shadow(color: Ad.aqua.opacity(0.35), radius: 24)
                .offset(y: -620)
                .scaleEffect(1.15 - 0.15 * pop(local, 0, 0.3))
            LiveFrame(image: a.live(c.0 + local), u: u, tint: c.2 == .white ? Ad.aqua : c.2)
                .scaleEffect(1.04 - 0.04 * pop(local, 0, 0.3))
                .offset(y: 40)
            Text("Every alert, iPhone-style")
                .font(.system(size: 32, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                .offset(y: 520).opacity(ramp(u, 0.5, 0.9))
        }
        .envelope(u, len)
    }
}

private struct TimersScene: View {
    let u: Double
    let a: Ad.Assets
    var body: some View {
        let len = Ad.toasts - Ad.timers
        let first = u < 1.4
        let rt = first ? 15.0 + u : 17.2 + (u - 1.4)          // timer tab, then the stopwatch bubble
        ZStack {
            Headline(top: "Timers.", bottom: "Stopwatch. Focus.", u: u - 0.1, y: -640, size: 96)
            LiveFrame(image: a.live(rt), u: u, tint: .orange)
                .scaleEffect(first ? 1 : 1.0 + 0.04 * (1 - pop(u, 1.4, 0.3)))
                .offset(y: 40)
            Text("Pomodoro sessions · a stopwatch bubble · chimes")
                .font(.system(size: 30, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                .offset(y: 520).opacity(ramp(u, 0.6, 1.0))
        }
        .envelope(u, len)
    }
}

// MARK: - Scenes

private struct LogoScene: View {
    let u: Double
    var body: some View {
        let draw = ramp(u, 0.0, 0.9)
        let out = ramp(u, 2.15, 2.6)
        ZStack {
            // Light streak swooping in
            Path { p in
                p.move(to: CGPoint(x: -100, y: 1150))
                p.addCurve(to: CGPoint(x: 1180, y: 760), control1: CGPoint(x: 300, y: 1300), control2: CGPoint(x: 700, y: 650))
            }
            .trim(from: max(0, draw - 0.35), to: draw)
            .stroke(Ad.aqua, style: StrokeStyle(lineWidth: 10, lineCap: .round))
            .shadow(color: Ad.aqua, radius: 20)
            .blendMode(.plusLighter)
            .opacity(1 - ramp(u, 0.9, 1.2))

            VStack(spacing: 30) {
                if let logo = Brand.appLogo {
                    Image(nsImage: logo).resizable().interpolation(.high).scaledToFit()
                        .frame(width: 520, height: 520)
                        .mask(RadialGradient(colors: [.black, .black, .clear], center: .center, startRadius: 0, endRadius: 250))
                        .blendMode(.screen)
                        .scaleEffect(0.5 + 0.5 * pop(u, 0.75, 0.6))
                        .opacity(ramp(u, 0.75, 1.0))
                        .shadow(color: Ad.aqua.opacity(0.8), radius: 40)
                }
                Text("2.0 · AQUATIC")
                    .font(.system(size: 54, weight: .heavy))
                    .tracking(28 + 18 * ramp(u, 1.1, 2.4))
                    .foregroundStyle(.white)
                    .opacity(ramp(u, 1.1, 1.4))
            }
            // Lens flare across the logo
            Ellipse().fill(RadialGradient(colors: [.white.opacity(0.9), Ad.aqua.opacity(0.4), .clear], center: .center, startRadius: 0, endRadius: 300))
                .frame(width: 700, height: 60)
                .offset(x: -500 + 1000 * ramp(u, 0.9, 1.6), y: -60)
                .opacity(ramp(u, 0.9, 1.0) * (1 - ramp(u, 1.5, 1.7)))
                .blendMode(.plusLighter)
        }
        .scaleEffect(1 + 0.6 * out)
        .opacity(1 - out)
    }
}

private struct LaptopScene: View {
    let u: Double
    var body: some View {
        let len = Ad.music - Ad.laptop
        let fly = ramp(u, 0, 0.8)
        let dive = ramp(u, len - 0.9, len)
        ZStack {
            Headline(top: "Your notch.", bottom: dive > 0.02 ? nil : "Now it's alive.", u: u - 0.4, y: -620)
                .opacity(1 - ramp(u, len - 1.0, len - 0.7))
            MacBook(u: u)
                .rotation3DEffect(.degrees(40 * (1 - fly)), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
                .rotation3DEffect(.degrees(-25 * (1 - fly) + 4 * sin(u * 1.2)), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                .offset(y: 300 * (1 - fly) + 60)
                .opacity(fly)
                // Camera dives into the notch
                .scaleEffect(1 + 6 * dive * dive, anchor: UnitPoint(x: 0.5, y: 0.205))
        }
    }
}

private struct MacBook: View {
    let u: Double
    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 30, style: .continuous).fill(Color(white: 0.12))
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.08, green: 0.12, blue: 0.3), Color(red: 0.3, green: 0.14, blue: 0.45),
                                                  Color(red: 0.05, green: 0.35, blue: 0.5)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .padding(16)
                // The notch, with a little island pulse
                let w: CGFloat = 150 + 80 * CGFloat(pop(u, 1.4, 0.5)) - 80 * CGFloat(ramp(u, 2.0, 2.3))
                UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 14, bottomTrailingRadius: 14, topTrailingRadius: 0)
                    .fill(.black)
                    .frame(width: w, height: 30)
                    .padding(.top, 16)
                    .shadow(color: Ad.aqua.opacity(0.8 * ramp(u, 1.3, 1.6)), radius: 18)
            }
            .frame(width: 900, height: 590)
            // Base
            UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 26, bottomTrailingRadius: 26, topTrailingRadius: 4)
                .fill(LinearGradient(colors: [Color(white: 0.55), Color(white: 0.25)], startPoint: .top, endPoint: .bottom))
                .frame(width: 1010, height: 34)
        }
        .shadow(color: Ad.aqua.opacity(0.35), radius: 70)
    }
}

private struct MusicScene: View {
    let u: Double
    let a: Ad.Assets
    var body: some View {
        let len = Ad.live - Ad.music
        let compact = a.img["01-compact-music"], full = a.img["02-music"]
        let w1: CGFloat = 520, w2: CGFloat = 960
        let toCompact = pop(u, 0.25, 0.5)
        let w = u < 1.6 ? 230 + (w1 - 230) * CGFloat(toCompact) : morph(u, 1.6, w1, w2, len: 0.6)
        let h = u < 1.6 ? 44 + (aspectH(compact, w1, fallback: 60) - 44) * CGFloat(toCompact)
            : morph(u, 1.6, aspectH(compact, w1, fallback: 60), aspectH(full, w2, fallback: 400), len: 0.6)
        let img = u < 1.6 ? compact : full
        let fade = u < 1.6 ? ramp(u, 0.45, 0.7) : ramp(u, 1.95, 2.25)
        ZStack {
            Headline(top: "Music,", bottom: "live in your notch.", u: u - 0.1, y: -680, size: 88)
            ScreenTop(u: u) {
                IslandBlob(w: w, h: h, image: img, contentOpacity: fade, glow: 0.5 + 0.4 * Ad.pulse(u + Ad.music))
            }
            .scaleEffect(1.02 + 0.04 * u / len)
            .offset(y: 120)
            Text("Spotify · Apple Music · your iPhone")
                .font(.system(size: 34, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                .offset(y: 620).opacity(ramp(u, 2.4, 2.8))
        }
        .envelope(u, len)
    }
}

private struct LyricsScene: View {
    let u: Double
    let a: Ad.Assets
    var body: some View {
        let len = Ad.vinyl - Ad.lyrics
        ZStack {
            if let shot = a.img["15-lyrics"] {
                Image(nsImage: shot).resizable().interpolation(.high).scaledToFit()
                    .frame(width: 960)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(.white.opacity(0.2), lineWidth: 2))
                    .shadow(color: Color.purple.opacity(0.6), radius: 60)
                    .rotation3DEffect(.degrees(18 - 10 * u / len), axis: (x: 0.2, y: 1, z: 0), perspective: 0.5)
                    .rotation3DEffect(.degrees(12), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
                    .scaleEffect(0.95 + 0.06 * u / len)
                    .offset(y: -330)
            }
            VStack(spacing: 22) {
                SweepLine(text: "Your jacket on my", start: 0.5, dur: 0.9, u: u, size: 84)
                SweepLine(text: "shoulders, radio low", start: 1.4, dur: 1.0, u: u, size: 84)
            }
            .offset(y: 380)
            Text("LYRICS · WORD BY WORD · IN SYNC")
                .font(.system(size: 28, weight: .bold)).tracking(5).foregroundStyle(Ad.aqua)
                .offset(y: 700).opacity(ramp(u, 0.3, 0.6))
        }
        .envelope(u, len)
    }
}

/// A line of lyrics that fills with light word by word.
private struct SweepLine: View {
    let text: String
    let start: Double
    let dur: Double
    let u: Double
    let size: CGFloat
    var fill: Color = Ad.aqua

    var body: some View {
        let words = text.split(separator: " ").map(String.init)
        let per = dur / Double(words.count)
        HStack(spacing: size * 0.25) {
            ForEach(Array(words.enumerated()), id: \.offset) { i, w in
                let p = max(0, min(1, (u - start - Double(i) * per) / per))
                let font = Font.system(size: size, weight: .heavy)
                Text(w).font(font).foregroundStyle(.white.opacity(0.28))
                    .overlay {
                        Text(w).font(font).foregroundStyle(fill)
                            .mask(LinearGradient(colors: [.black, .clear], startPoint: UnitPoint(x: p * 1.3 - 0.3, y: 0.5),
                                                 endPoint: UnitPoint(x: p * 1.3, y: 0.5)))
                            .shadow(color: fill.opacity(0.9 * p * (1 - p) * 4), radius: 18)
                    }
                    .offset(y: -6 * p)
                    .scaleEffect(1 + 0.06 * p * (1 - p) * 4)
            }
        }
        .fixedSize()
        .opacity(ramp(u, start - 0.4, start - 0.1))
    }
}

private struct VinylScene: View {
    let u: Double
    let art: NSImage?
    var body: some View {
        let len = Ad.karaoke - Ad.vinyl
        let slide = ramp(u, 0.2, 0.9)
        ZStack {
            Headline(top: "Spin it.", u: u - 0.1, y: -700, size: 120)
            ZStack {
                RecordDisc(art: art, accent: .pink, size: 760)
                    .rotationEffect(.degrees(u * 260))
                    .offset(y: -40 + 330 * slide)
                    .shadow(color: .pink.opacity(0.4), radius: 50)
                if let art {
                    Image(nsImage: art).resizable().frame(width: 760, height: 760)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(LinearGradient(colors: [.white.opacity(0.15), .clear, .black.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .shadow(color: .black.opacity(0.6), radius: 30, y: 20)
                        .offset(y: -40 - 330 * slide)
                        .rotation3DEffect(.degrees(10 * sin(u * 1.5)), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                }
            }
            .scaleEffect(0.8 + 0.2 * pop(u, 0, 0.5))
            .offset(y: 120)
            Text("VINYL MODE · 33⅓ RPM")
                .font(.system(size: 28, weight: .bold)).tracking(5).foregroundStyle(.pink)
                .offset(y: 820).opacity(ramp(u, 0.8, 1.1))
        }
        .envelope(u, len)
    }
}

private struct KaraokeScene: View {
    let u: Double
    let art: NSImage?
    var body: some View {
        let len = Ad.calls - Ad.karaoke
        let b = Ad.beat
        let score = Int(97 * ramp(u, 1.9, 3.0))
        ZStack {
            Headline(top: "Sing it.", u: u - 0.1, y: -700, size: 120)
            // 3 · 2 · 1 on the beat
            HStack(spacing: 46) {
                ForEach(0..<3, id: \.self) { i in
                    let on = u < 0.4 + Double(i + 1) * b * 1.0
                    Circle().fill(.white.opacity(on ? 0.95 : 0.15)).frame(width: 64, height: 64)
                        .scaleEffect(on ? 1 : 0.6)
                        .shadow(color: Ad.aqua.opacity(on ? 0.8 : 0), radius: 20)
                }
            }
            .offset(y: -260)
            .opacity(1 - ramp(u, 1.8, 2.0))
            VStack(spacing: 30) {
                SweepLine(text: "Singing every word", start: 1.6, dur: 0.9, u: u, size: 92)
                SweepLine(text: "we didn't know", start: 2.5, dur: 0.6, u: u, size: 92)
            }
            .offset(y: 40)
            // Mic meter + score
            HStack(spacing: 40) {
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(0..<14, id: \.self) { i in
                        let lvl = 0.5 + 0.5 * sin(u * 13 + Double(i) * 0.8) * sin(u * 5.3 + Double(i))
                        let on = Double(i) / 14 < lvl * ramp(u, 1.5, 1.8)
                        Capsule().fill(on ? (i > 11 ? Color.red : (i > 8 ? .yellow : .green)) : .white.opacity(0.15))
                            .frame(width: 16, height: 30 + CGFloat(i) * 6)
                    }
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(score)").font(.system(size: 110, weight: .black, design: .rounded)).foregroundStyle(.white)
                        .monospacedDigit()
                    Text("SCORE").font(.system(size: 26, weight: .bold)).tracking(6).foregroundStyle(Ad.aqua)
                }
            }
            .offset(y: 560)
            .opacity(ramp(u, 1.4, 1.7))
        }
        .envelope(u, len)
    }
}

private struct CallsScene: View {
    let u: Double
    let a: Ad.Assets
    var body: some View {
        let len = Ad.focus - Ad.calls
        let ring = a.img["09-call-incoming"], active = a.img["11-compact-call"]
        let open = pop(u, 0.3, 0.55), close = pop(u, 1.9, 0.5)
        let wRing: CGFloat = 960, wAct: CGFloat = 560
        let hRing = aspectH(ring, wRing, fallback: 180), hAct = aspectH(active, wAct, fallback: 50)
        let w = u < 1.9 ? 230 + (wRing - 230) * CGFloat(open) : wRing + (wAct - wRing) * CGFloat(close)
        let h = u < 1.9 ? 44 + (hRing - 44) * CGFloat(open) : hRing + (hAct - hRing) * CGFloat(close)
        let ringPulse = 0.5 + 0.5 * sin(u * 14)
        ZStack {
            Headline(top: "Calls.", bottom: "The instant they ring.", u: u - 0.1, y: -680, size: 88)
            ScreenTop(u: u) {
                IslandBlob(w: w, h: h, image: u < 1.9 ? ring : active,
                           contentOpacity: u < 1.9 ? ramp(u, 0.5, 0.75) : ramp(u, 2.05, 2.3),
                           glow: u < 1.9 ? 0.5 + 0.5 * ringPulse : 0.6, glowColor: .green)
            }
            .offset(y: 120)
            Text("iPhone · FaceTime Audio · FaceTime Video")
                .font(.system(size: 32, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                .offset(y: 620).opacity(ramp(u, 0.8, 1.2))
        }
        .envelope(u, len)
    }
}

private struct WidgetsScene: View {
    let u: Double
    let a: Ad.Assets
    var body: some View {
        let len = Ad.tools - Ad.widgets
        let b = Ad.beat
        // Final grid positions (centre offsets) for the six widgets, as on the sheet.
        let pos: [CGPoint] = [CGPoint(x: 0, y: -330), CGPoint(x: -172, y: 0), CGPoint(x: 172, y: 0),
                              CGPoint(x: -172, y: 344), CGPoint(x: 172, y: 344), CGPoint(x: 0, y: 674)]
        let from: [CGPoint] = [CGPoint(x: 0, y: -1400), CGPoint(x: -1200, y: 0), CGPoint(x: 1200, y: 0),
                               CGPoint(x: -1200, y: 600), CGPoint(x: 1200, y: 600), CGPoint(x: 0, y: 1500)]
        ZStack {
            Headline(top: "Widgets.", bottom: "Even on your Lock Screen.", u: u - 0.1, y: -760, size: 80)
            ZStack {
                ForEach(Array(a.widgets.enumerated()), id: \.offset) { i, img in
                    let p = pop(u, 0.3 + Double(i) * b * 0.5, 0.5)
                    Image(nsImage: img).resizable().interpolation(.high)
                        .frame(width: img.size.width, height: img.size.height)
                        .shadow(color: Ad.aqua.opacity(0.3), radius: 24)
                        .rotation3DEffect(.degrees(50 * (1 - p)), axis: (x: 1, y: 1, z: 0), perspective: 0.5)
                        .offset(x: from[i].x + (pos[i].x - from[i].x) * CGFloat(p), y: from[i].y + (pos[i].y - from[i].y) * CGFloat(p))
                        .opacity(min(1, p * 2))
                }
            }
            .scaleEffect(0.95 + 0.05 * u / len)
            .rotation3DEffect(.degrees(6 * sin(u)), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            .offset(y: 80)
        }
        .envelope(u, len)
    }
}

private struct ToolsScene: View {
    let u: Double
    let a: Ad.Assets
    var body: some View {
        let len = Ad.timers - Ad.tools
        let tools = a.img["08b-tools"]
        let open = pop(u, 0.2, 0.55)
        let w: CGFloat = 230 + (960 - 230) * CGFloat(open)
        let h: CGFloat = 44 + (aspectH(tools, 960, fallback: 380) - 44) * CGFloat(open)
        let tiles: [(String, String, Color)] = [("function", "Calculator", .orange), ("cup.and.saucer.fill", "Keep Awake", .orange),
                                               ("eyedropper.halffull", "Color Picker", .pink), ("camera.viewfinder", "Screenshot", .cyan),
                                               ("moon.fill", "Dark Mode", .indigo), ("centsign.circle.fill", "Coin Flip", .yellow)]
        ZStack {
            Headline(top: "Tools,", bottom: "one tap away.", u: u - 0.1, y: -700, size: 96)
            if a.footage != nil {
                LiveFrame(image: a.live(9.3 + min(u, 2.3)), u: u).offset(y: -60)
            } else {
                ScreenTop(u: u) {
                    IslandBlob(w: w, h: h, image: tools, contentOpacity: ramp(u, 0.45, 0.7), glow: 0.6)
                }
                .offset(y: -40)
            }
            // Tiles flying out of the island, one per beat
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(300), spacing: 24), count: 3), spacing: 24) {
                ForEach(Array(tiles.enumerated()), id: \.offset) { i, tile in
                    let p = pop(u, 0.9 + Double(i) * Ad.beat * 0.5, 0.45)
                    HStack(spacing: 14) {
                        Image(systemName: tile.0).font(.system(size: 30, weight: .bold)).foregroundStyle(tile.2)
                        Text(tile.1).font(.system(size: 26, weight: .bold)).foregroundStyle(.white)
                    }
                    .frame(width: 300, height: 92)
                    .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.white.opacity(0.09)))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(tile.2.opacity(0.5), lineWidth: 1.5))
                    .scaleEffect(0.3 + 0.7 * p)
                    .opacity(min(1, p * 2))
                    .offset(y: -200 * (1 - p))
                }
            }
            .frame(width: 960)
            .offset(y: 620)
        }
        .envelope(u, len)
    }
}

/// Rapid-fire island moments on the beat: the island morphs into a new alert every beat.
private struct ToastsScene: View {
    let u: Double
    static let items: [(String, Color, String, String)] = [
        ("moon.fill", .indigo, "Do Not Disturb", "On"), ("airpodspro", .white, "AirPods Pro", "Connected"),
        ("bolt.fill", .green, "Charging", "80%"), ("capslock.fill", .green, "Caps Lock", "On"),
        ("timer", .orange, "Timer", "24:59"), ("bicycle", .orange, "Pizza", "65%"),
        ("heart.fill", .pink, "Liked Songs", "Added"), ("arrow.down.circle.fill", .green, "Download", "100%"),
        ("lock.open.fill", .white, "Welcome back", "Unlocked"),
    ]
    var body: some View {
        let len = Ad.hype - Ad.toasts
        let b = Ad.beat
        let i = min(Self.items.count - 1, max(0, Int((u - 0.2) / b)))
        let local = u - 0.2 - Double(i) * b
        let it = Self.items[i]
        let width: CGFloat = 640 + 60 * CGFloat(i % 3)
        let p = pop(local, 0, 0.32)
        ZStack {
            Headline(top: "It does", bottom: "everything.", u: u - 0.1, y: -680, size: 110)
            ScreenTop(u: u) {
                ZStack {
                    IslandBlob(w: 230 + (width - 230) * CGFloat(p), h: 64 + 14 * CGFloat(p), glow: 0.5 + 0.5 * p, glowColor: it.1 == .white ? Ad.aqua : it.1)
                    HStack {
                        Image(systemName: it.0).font(.system(size: 34, weight: .bold)).foregroundStyle(it.1)
                        Text(it.2).font(.system(size: 30, weight: .bold)).foregroundStyle(.white)
                        Spacer()
                        Text(it.3).font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(it.1 == .white ? Ad.aqua : it.1)
                    }
                    .padding(.horizontal, 36)
                    .frame(width: width, height: 78)
                    .opacity(ramp(local, 0.08, 0.2))
                    .scaleEffect(0.8 + 0.2 * p)
                }
            }
            .offset(y: 160)
            .scaleEffect(1.05)
            // Feature name flashing big under the screen
            Text(it.2.uppercased())
                .font(.system(size: 40, weight: .heavy)).tracking(8)
                .foregroundStyle(.white.opacity(0.85))
                .offset(y: 660)
                .scaleEffect(1.2 - 0.2 * p)
                .opacity(p)
        }
        .envelope(u, len)
    }
}

private struct HypeScene: View {
    let u: Double
    var body: some View {
        let len = Ad.end - Ad.hype
        let words = ["Everything", "your", "notch", "can", "be."]
        let b = Ad.beat
        let slamAt = Double(words.count) * b + 0.25
        let slam = u - slamAt
        ZStack {
            if slam < 0.15 {
                VStack(spacing: 0) {
                    ForEach(Array(words.enumerated()), id: \.offset) { i, w in
                        let p = pop(u, Double(i) * b, 0.3)
                        Text(w)
                            .font(.system(size: i == 2 ? 190 : 140, weight: .black))
                            .foregroundStyle(i == 2 ? AnyShapeStyle(LinearGradient(colors: [Ad.aqua, .white], startPoint: .leading, endPoint: .trailing)) : AnyShapeStyle(.white))
                            .scaleEffect(0.3 + 0.7 * p)
                            .opacity(min(1, p * 2))
                    }
                }
                .opacity(1 - ramp(slam, -0.1, 0.1))
            }
            if slam > -0.05 {
                let p = pop(slam, 0, 0.45)
                ZStack {
                    ForEach(0..<3, id: \.self) { r in
                        let rp = ramp(slam, Double(r) * 0.12, Double(r) * 0.12 + 0.9)
                        Circle().stroke(Ad.aqua.opacity(0.6 * (1 - rp)), lineWidth: 6)
                            .frame(width: 200 + 1600 * rp, height: 200 + 1600 * rp)
                    }
                    Text("2.0")
                        .font(.system(size: 480, weight: .black, design: .rounded))
                        .foregroundStyle(LinearGradient(colors: [.white, Ad.aqua, Color(red: 0.35, green: 0.4, blue: 1)],
                                                        startPoint: .topLeading, endPoint: .bottomTrailing))
                        .shadow(color: Ad.aqua.opacity(0.9), radius: 70)
                        .scaleEffect(2.4 - 1.4 * p + 0.04 * max(0, slam))
                    LetteringShape("Aquatic", size: 140)
                        .fill(LinearGradient(colors: [.white, Ad.aqua], startPoint: .leading, endPoint: .trailing))
                        .frame(width: 700, height: 200)
                        .offset(y: 360)
                        .opacity(ramp(slam, 0.4, 0.8))
                        .shadow(color: Ad.aqua.opacity(0.7), radius: 30)
                }
                .opacity(min(1, slam * 8))
            }
        }
        .opacity(1 - ramp(u, len - 0.2, len))
    }
}

private struct AdEndScene: View {
    let u: Double
    var body: some View {
        VStack(spacing: 34) {
            if let logo = Brand.appLogo {
                Image(nsImage: logo).resizable().interpolation(.high).scaledToFit()
                    .frame(width: 420, height: 420)
                    .mask(RadialGradient(colors: [.black, .black, .clear], center: .center, startRadius: 0, endRadius: 200))
                    .blendMode(.screen)
                    .shadow(color: Ad.aqua.opacity(0.7), radius: 40)
                    .scaleEffect(0.5 + 0.5 * pop(u, 0, 0.6))
                    .rotation3DEffect(.degrees(40 * (1 - ramp(u, 0, 1))), axis: (x: 0, y: 1, z: 0))
                    .opacity(ramp(u, 0, 0.4))
            }
            KineticText(text: "Aries Dynamic Island", u: u - 0.4, size: 82, weight: .black)
            Text("2.0 Aquatic")
                .font(.system(size: 46, weight: .bold, design: .rounded))
                .foregroundStyle(LinearGradient(colors: [.white, Ad.aqua], startPoint: .leading, endPoint: .trailing))
                .opacity(ramp(u, 0.9, 1.3))
            Text("Free download on GitHub")
                .font(.system(size: 38, weight: .heavy))
                .foregroundStyle(.black)
                .padding(.horizontal, 46).frame(height: 96)
                .background(Capsule().fill(.white))
                .shadow(color: Ad.aqua.opacity(0.6 + 0.4 * sin(u * 4)), radius: 34)
                .scaleEffect(0.5 + 0.5 * pop(u, 1.4, 0.5))
                .opacity(ramp(u, 1.4, 1.6))
                .padding(.top, 20)
            Text("A  MAXX  FORGE  STUDIO  PRODUCT")
                .font(.system(size: 24, weight: .semibold)).tracking(5)
                .foregroundStyle(.white.opacity(0.55))
                .opacity(ramp(u, 2.0, 2.5))
                .padding(.top, 30)
        }
        .scaleEffect(1 + 0.03 * u / 5)
    }
}

// MARK: - Sound: 128 bpm, original, loud

/// An energetic, original 128 bpm track (four-on-the-floor kick, sidechained supersaws, rolling bass,
/// a lead hook, snare-roll builds into big drops) with an optional voiceover mixed on top.
enum AdAudio {
    static let rate = 44100.0

    /// Voiceover lines: file name → start time.
    static var voPlan: [(String, Double)] {
        let slam = Ad.hype + 5 * Ad.beat + 0.25
        return [("vo1", Ad.laptop + 0.4), ("vo2", Ad.music + 0.25), ("vo3", Ad.lyrics + 0.3), ("vo4", Ad.calls + 0.3),
                ("vo5", Ad.toasts + 0.3), ("vo6", Ad.hype + 0.08), ("vo7", slam + 0.55), ("vo8", Ad.end + 1.4)]
    }

    static func render(to url: URL, vo: URL? = nil) throws {
        let d = Ad.duration, n = Int(d * rate), b = Ad.beat, bar = 4 * b
        var drums = [Float](repeating: 0, count: n * 2)       // interleaved L/R
        var music = [Float](repeating: 0, count: n * 2)       // gets sidechained
        var fx = [Float](repeating: 0, count: n * 2)

        func add(_ buf: inout [Float], _ t0: Double, _ len: Double, _ gain: Double, pan: Double = 0, _ f: (Double) -> Double) {
            let s0 = max(0, Int(t0 * rate)), s1 = min(n, Int((t0 + len) * rate))
            guard s1 > s0 else { return }
            let gl = Float(gain * (1 - max(0, pan))), gr = Float(gain * (1 + min(0, pan)))
            for i in s0..<s1 { let v = Float(f(Double(i) / rate - t0)); buf[2 * i] += v * gl; buf[2 * i + 1] += v * gr }
        }
        func saw(_ ph: Double) -> Double { 2 * (ph - floor(ph)) - 1 }
        func noise() -> Double { Double.random(in: -1...1) }

        let slam = Ad.hype + 5 * b + 0.25
        let grooveStart = Ad.music                 // the first drop
        let buildStart = Ad.laptop
        let breakStart = Ad.hype                    // second build
        let grooveEnd = Ad.end + 2 * bar           // groove rides into the end card
        func inGroove(_ t: Double) -> Bool { (t >= grooveStart && t < breakStart) || (t >= slam && t < grooveEnd) }

        // Am – F – C – G
        let roots: [Double] = [55.0, 43.65, 65.41, 49.0]
        let chords: [[Double]] = [[220, 261.63, 329.63, 440], [174.61, 220, 261.63, 349.23],
                                  [196, 261.63, 329.63, 392], [196, 246.94, 293.66, 392]]
        let hook: [Int] = [0, 2, 3, 2, 1, 2, 3, 2, 0, 2, 3, 4, 3, 2, 1, 2]
        func chordIndex(_ t: Double) -> Int { Int(max(0, t - grooveStart) / bar) % 4 }

        // ── Intro: shimmer + logo impact
        add(&music, 0, Ad.laptop + 0.2, 0.16) { x in
            let e = min(1, x / 1.2)
            return e * (sin(2 * .pi * 440 * x) * 0.3 + sin(2 * .pi * 659.25 * x) * 0.25 + sin(2 * .pi * 880.6 * x) * 0.2 + sin(2 * .pi * 1318.5 * x) * 0.1)
        }
        add(&fx, 0.75, 2.0, 0.9) { x in sin(2 * .pi * (34 + 80 * exp(-x * 9)) * x) * exp(-x * 2.2) }
        add(&fx, 0.75, 0.5, 0.3) { x in noise() * exp(-x * 10) }

        // ── Beat grid
        var t = buildStart
        var beatN = 0
        while t < grooveEnd - 0.001 {
            let groove = inGroove(t)
            let building = t >= buildStart && t < grooveStart
            let breaking = t >= breakStart && t < slam
            let ci = chordIndex(t)
            // Kick (also in the first build, filtered-sounding via shorter decay)
            if groove || building {
                let g = groove ? 1.0 : 0.7
                add(&drums, t, 0.45, 0.95 * g) { x in sin(2 * .pi * (46 + 120 * exp(-x * 38)) * x) * exp(-x * 7) + (x < 0.004 ? noise() * 0.4 : 0) }
            }
            if groove {
                // Clap + snare on 2 & 4
                if beatN % 2 == 1 {
                    var lp = 0.0
                    add(&drums, t, 0.25, 0.42) { x in
                        let e = (x < 0.01 ? 0.7 : 1) * exp(-x * 18)
                        let nz = noise(); lp += 0.5 * (nz - lp)
                        return (nz - lp * 0.6) * e + sin(2 * .pi * 190 * x) * exp(-x * 30) * 0.5
                    }
                }
                // Open hat on the off-beat, closed 16ths
                var hp = 0.0
                add(&drums, t + b / 2, 0.16, 0.16, pan: 0.15) { x in let nz = noise(); hp += 0.7 * (nz - hp); return (nz - hp) * exp(-x * 16) }
                for k in [1, 3] {
                    var hp2 = 0.0
                    add(&drums, t + Double(k) * b / 4, 0.04, 0.07, pan: k == 1 ? -0.4 : 0.4) { x in let nz = noise(); hp2 += 0.8 * (nz - hp2); return (nz - hp2) * exp(-x * 90) }
                }
                // Rolling bass: 8ths, octave bounce
                let f = roots[ci]
                for k in 0..<2 {
                    let fk = k == 0 ? f : f * 2
                    var lp = 0.0
                    add(&music, t + Double(k) * b / 2, b / 2 * 0.95, 0.42) { x in
                        let v = saw(fk * 2 * x) * 0.6 + sin(2 * .pi * fk * x)
                        lp += 0.12 * (v - lp)
                        return lp * min(1, x * 200) * exp(-x * 3)
                    }
                }
                // Lead hook (16th plucks) in drops
                for k in 0..<4 {
                    let step = (beatN * 4 + k) % hook.count
                    let c = chords[ci]
                    let f = c[min(c.count - 1, hook[step])] * 2
                    add(&music, t + Double(k) * b / 4, 0.3, 0.085, pan: k % 2 == 0 ? -0.3 : 0.3) { x in
                        (saw(f * x) * 0.5 + sin(2 * .pi * f * x)) * exp(-x * 11)
                    }
                }
            }
            if building || breaking {
                // Hats tighten up toward the drop
                var hp = 0.0
                add(&drums, t + b / 2, 0.06, 0.08) { x in let nz = noise(); hp += 0.8 * (nz - hp); return (nz - hp) * exp(-x * 50) }
            }
            if breaking {
                // Hype words: a punchy hit on each beat
                add(&drums, t, 0.5, 0.8) { x in sin(2 * .pi * (40 + 100 * exp(-x * 30)) * x) * exp(-x * 6) }
                add(&drums, t, 0.2, 0.3) { x in noise() * exp(-x * 20) }
            }
            t += b; beatN += 1
        }

        // ── Supersaw chords, one per bar, in grooves (plus a filtered version in the builds)
        var cbar = Ad.laptop
        while cbar < grooveEnd {
            let ci = chordIndex(cbar)
            let full = inGroove(cbar + 0.01)
            let gain = full ? 0.10 : 0.05
            let c = chords[ci]
            var lpL = 0.0, lpR = 0.0
            let cutoff = full ? 0.18 : 0.05
            let s0 = Int(cbar * rate), s1 = min(n, Int((cbar + bar) * rate))
            if s1 > s0 {
                for i in s0..<s1 {
                    let x = Double(i) / rate - cbar
                    var l = 0.0, r = 0.0
                    for f in c {
                        for (k, det) in [-0.012, -0.006, 0.0, 0.006, 0.012].enumerated() {
                            let v = saw(f * (1 + det) * x + Double(k) * 0.37)
                            if k % 2 == 0 { l += v } else { r += v }
                            if k == 2 { r += v }
                        }
                    }
                    lpL += cutoff * (l - lpL); lpR += cutoff * (r - lpR)
                    let env = min(1, x / 0.02) * (x > bar - 0.05 ? max(0, (bar - x) / 0.05) : 1)
                    music[2 * i] += Float(lpL * gain * env / 6); music[2 * i + 1] += Float(lpR * gain * env / 6)
                }
            }
            cbar += bar
        }

        // ── Builds: snare rolls + risers
        func build(from a: Double, to z: Double) {
            var tt = a
            while tt < z - 0.01 {
                let k = (tt - a) / (z - a)
                let step = k < 0.5 ? b / 2 : (k < 0.8 ? b / 4 : b / 8)
                add(&drums, tt, 0.12, 0.12 + 0.3 * k) { x in noise() * exp(-x * 30) + sin(2 * .pi * 200 * x) * exp(-x * 40) * 0.4 }
                tt += step
            }
            var lp = 0.0
            add(&fx, a, z - a, 0.4) { x in
                let k = x / (z - a)
                lp += (0.01 + 0.5 * k * k) * (noise() - lp)
                return (lp + 0.25 * sin(2 * .pi * (180 + 1600 * k * k) * x)) * k * k
            }
        }
        build(from: buildStart + 2 * b, to: grooveStart)
        build(from: breakStart, to: slam)

        // ── Drops: impacts
        for at in [grooveStart, slam] {
            add(&fx, at, 2.8, 1.0) { x in sin(2 * .pi * (30 + 90 * exp(-x * 9)) * x) * exp(-x * 1.5) }
            add(&fx, at, 1.0, 0.45) { x in noise() * exp(-x * 6) }
        }
        // Whooshes into the other cuts
        for c in Ad.cuts where c > grooveStart + 0.1 && abs(c - slam) > 0.5 && c < Ad.end {
            var lp = 0.0
            add(&fx, c - 0.3, 0.38, 0.22) { x in
                lp += (0.05 + 0.4 * min(1, x / 0.3)) * (noise() - lp)
                return lp * min(1, x / 0.3) * (x > 0.3 ? exp(-(x - 0.3) * 40) : 1)
            }
        }
        // ── End: big chord ringing out
        let fin: [Double] = [110, 220, 261.63, 329.63, 440, 523.25, 659.25, 880]
        add(&music, grooveEnd, d - grooveEnd, 0.28) { x in
            fin.reduce(0) { $0 + sin(2 * .pi * $1 * x) + 0.2 * sin(2 * .pi * $1 * 2.004 * x) } / Double(fin.count) * min(1, x / 0.02) * exp(-x * 0.6)
        }
        add(&fx, grooveEnd, 2.0, 0.8) { x in sin(2 * .pi * (34 + 70 * exp(-x * 9)) * x) * exp(-x * 2) }

        // ── Voiceover
        var voice = [Float](repeating: 0, count: n * 2)
        if let vo {
            for (name, at) in voPlan {
                guard let f = try? AVAudioFile(forReading: vo.appendingPathComponent(name + ".aiff")),
                      let buf = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(f.length)) else { continue }
                try? f.read(into: buf)
                guard let ch = buf.floatChannelData?[0] else { continue }
                let src = f.processingFormat.sampleRate, len = Int(buf.frameLength)
                let outLen = Int(Double(len) * rate / src)
                let s0 = Int(at * rate)
                for j in 0..<outLen {
                    let pos = Double(j) * src / rate
                    let i0 = Int(pos), fr = Float(pos - Double(i0))
                    guard i0 + 1 < len, s0 + j < n else { break }
                    var v = ch[i0] * (1 - fr) + ch[i0 + 1] * fr
                    v = tanhf(v * 2.2) * 0.9          // presence
                    voice[2 * (s0 + j)] += v; voice[2 * (s0 + j) + 1] += v
                    // short slap-back for size
                    let e = s0 + j + Int(0.045 * rate)
                    if e < n { voice[2 * e] += v * 0.18; voice[2 * e + 1] += v * 0.22 }
                }
            }
        }

        // ── Mix: sidechain pump on music, duck under the voice, loud master
        var voEnv: Float = 0
        var out = [Float](repeating: 0, count: n * 2)
        for i in 0..<n {
            let ts = Double(i) / rate
            var pump = 1.0
            if inGroove(ts) || (ts >= buildStart && ts < grooveStart) {
                let ph = (ts - buildStart).truncatingRemainder(dividingBy: b) / b
                pump = 0.25 + 0.75 * min(1, ph * 2.6)
            }
            let va = max(abs(voice[2 * i]), abs(voice[2 * i + 1]))
            voEnv = va > voEnv ? voEnv + 0.02 * (va - voEnv) : voEnv * 0.99992
            let duck = Float(1 - 0.5 * Double(min(1, voEnv * 6)))
            for c in 0..<2 {
                let m = music[2 * i + c] * Float(pump) * duck
                let mixed = drums[2 * i + c] * (0.6 + 0.4 * duck) + m * 1.25 + fx[2 * i + c] * 0.8 + voice[2 * i + c] * 1.35
                out[2 * i + c] = tanhf(mixed * 1.05)
            }
        }
        let peak = out.reduce(Float(0)) { max($0, abs($1)) }
        let norm = peak > 0 ? 0.97 / peak : 1
        let fmt = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
        let pcm = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(n))!
        pcm.frameLength = AVAudioFrameCount(n)
        for i in 0..<n {
            let fade = Float(min(1, (d - Double(i) / rate) / 0.8))
            pcm.floatChannelData![0][i] = out[2 * i] * norm * fade
            pcm.floatChannelData![1][i] = out[2 * i + 1] * norm * fade
        }
        try? FileManager.default.removeItem(at: url)
        let file = try AVAudioFile(forWriting: url, settings: fmt.settings)
        try file.write(from: pcm)
    }
}

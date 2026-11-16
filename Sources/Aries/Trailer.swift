import AppKit
import AVFoundation
import SwiftUI

/// The Aries 2.0 "Aquatic" launch trailer, rendered frame by frame from the real app's screens:
/// brand intro → "Welcome to Aquatic" → hype → nine hero features → "and so much more" montage →
/// download card, over an original synthesized soundtrack.
/// Run: `Aries --render-trailer <outDir> <screenshotsDir>` (add `--preview` for a few stills).
enum Trailer {
    struct Scene {
        let image: String
        let title: String
        let sub: String
        let tint: Color
    }

    static let bpm = 120.0
    static var beat: Double { 60 / bpm }
    static let welcomeLen = 4.6
    static let hypeLen = 4.0
    static let sceneLen = 3.2
    static let montageLen = 10.0
    static let endLen = 6.5

    static let scenes: [Scene] = [
        .init(image: "02-music", title: "The Dynamic Island. On your Mac.", sub: "Spotify, Apple Music and your iPhone, live in the notch.", tint: .cyan),
        .init(image: "15-lyrics", title: "Lyrics, reimagined.", sub: "Word by word. Perfectly in sync.", tint: .purple),
        .init(image: "15b-vinyl", title: "Spin it on Vinyl.", sub: "A record that plays right along with you.", tint: .pink),
        .init(image: "15c-karaoke", title: "Sing it.", sub: "Karaoke mode, with a countdown and a score.", tint: .cyan),
        .init(image: "15e-artist", title: "Deeper Spotify.", sub: "Artists, albums, playlists and Play Next.", tint: .green),
        .init(image: "15d-widgets", title: "Widgets everywhere.", sub: "On your desktop, and on your Lock Screen.", tint: .orange),
        .init(image: "08b-tools", title: "Tools, one tap away.", sub: "Calculator, Keep Awake, Color Picker, Coin Flip.", tint: .yellow),
        .init(image: "09-call-incoming", title: "Calls, the instant they ring.", sub: "iPhone, FaceTime Audio and FaceTime Video.", tint: .green),
        .init(image: "05-home", title: "Your notch, alive.", sub: "Weather, calendar, Focus modes and a tiny ram.", tint: .indigo),
    ]

    /// Everything else, for the montage wall.
    static let wall = ["01-compact-music", "03-music-queue", "04-music-devices", "06-notes", "07-shelf", "08-timer",
                       "10-call-active", "12-song-toast", "14-volume", "15f-album", "16-player", "20-settings-music",
                       "21-compact-download", "22-whats-new", "23-bubble-timer", "24-activity", "11-compact-call",
                       "13-liked-toast", "20-settings-shortcuts", "20-settings-updates"]

    static let chips: [(String, String)] = [
        ("note.text", "Notes & To-Dos"), ("tray.full.fill", "File Shelf"), ("timer", "Timers"), ("brain.head.profile", "Focus Sessions"),
        ("stopwatch.fill", "Stopwatch"), ("speaker.wave.3.fill", "Volume HUD"), ("bolt.horizontal.circle.fill", "Live Activities"),
        ("arrow.down.circle.fill", "Downloads"), ("hifispeaker.2.fill", "Play on Any Device"), ("list.bullet", "Up Next"),
        ("moon.fill", "Focus Modes"), ("capslock.fill", "Caps Lock"), ("battery.25percent", "Low Power Mode"),
        ("cloud.sun.fill", "Weather"), ("calendar", "Calendar"), ("doc.on.clipboard.fill", "Clipboard"),
        ("person.crop.square.fill", "Mirror"), ("eyedropper.halffull", "Color Picker"), ("cup.and.saucer.fill", "Keep Awake"),
        ("drop.fill", "Glass Island"), ("hand.draw.fill", "Swipe to Skip"), ("accessibility", "Accessibility"),
        ("arrow.triangle.2.circlepath", "Auto Updates"), ("heart.fill", "Like Songs"),
    ]

    static var welcomeStart: Double { BrandIntro.duration }
    static var hypeStart: Double { welcomeStart + welcomeLen }
    static var featuresStart: Double { hypeStart + hypeLen }
    static var montageStart: Double { featuresStart + Double(scenes.count) * sceneLen }
    static var endStart: Double { montageStart + montageLen }
    static var duration: Double { endStart + endLen }
    static var cuts: [Double] {
        [welcomeStart, hypeStart, featuresStart] + scenes.indices.dropFirst().map { featuresStart + Double($0) * sceneLen }
            + [montageStart, endStart]
    }

    static let crops: [String: Int] = [
        "02-music": 208, "03-music-queue": 268, "04-music-devices": 268, "05-home": 138, "06-notes": 246, "07-shelf": 142,
        "08-timer": 130, "08b-tools": 198, "09-call-incoming": 124, "10-call-active": 124,
    ]

    /// Loads a screenshot; island shots are cropped to the island (dropping the empty wallpaper).
    static func load(_ dir: URL, _ name: String, maxSide: CGFloat = 1800) -> NSImage? {
        guard let img = NSImage(contentsOf: dir.appendingPathComponent(name + ".png")),
              var cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let island = cg.width == 1640 && cg.height == 680
        if island, let data = cg.dataProvider?.data, let p = CFDataGetBytePtr(data) {
            let w = cg.width, h = cg.height, bpr = cg.bytesPerRow, bpp = cg.bitsPerPixel / 8
            var minX = w, maxX = 0, maxY = 0
            for y in stride(from: 0, to: h, by: 2) {
                for x in stride(from: 0, to: w, by: 2) {
                    let o = y * bpr + x * bpp
                    if (Int(p[o]) + Int(p[o + 1]) + Int(p[o + 2])) / 3 < 30 { minX = min(minX, x); maxX = max(maxX, x); maxY = max(maxY, y) }
                }
            }
            if maxX > minX {
                let pad = 40
                let bottom = crops[name].map { min(h, $0 * 2 + 36) } ?? min(h, maxY + pad)
                let r = CGRect(x: max(0, minX - pad), y: 0, width: min(w, maxX + pad) - max(0, minX - pad), height: bottom)
                if let c = cg.cropping(to: r) { cg = c }
            }
        }
        // Downscale big images once so every frame renders fast.
        let k = min(1, maxSide / CGFloat(max(cg.width, cg.height)))
        let size = NSSize(width: CGFloat(cg.width) * k, height: CGFloat(cg.height) * k)
        let out = NSImage(size: size)
        out.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        NSImage(cgImage: cg, size: .zero).draw(in: NSRect(origin: .zero, size: size))
        out.unlockFocus()
        return out
    }

    @MainActor static func loadAll(_ shots: URL) -> [String: NSImage] {
        var images: [String: NSImage] = [:]
        for s in scenes { images[s.image] = load(shots, s.image) }
        for w in wall { images["wall:" + w] = load(shots, w, maxSide: 700) }
        return images
    }

    @MainActor static func render(outDir: URL, shots: URL) throws {
        let images = loadAll(shots)
        let size = CGSize(width: 1920, height: 1080)
        let silent = outDir.appendingPathComponent("trailer-video.mp4")
        try IntroExporter.renderVideo(to: silent, size: size, fps: 60, duration: duration, frame: { t, sz in
            let r = ImageRenderer(content: TrailerView(t: t, images: images).frame(width: sz.width, height: sz.height))
            r.scale = 1
            r.proposedSize = ProposedViewSize(sz)
            return r.cgImage
        }, progress: { p in print(String(format: "video %.0f%%", p * 100)); fflush(stdout) })

        let wav = outDir.appendingPathComponent("trailer-audio.wav")
        try TrailerAudio.render(to: wav, duration: duration)
        print("audio done"); fflush(stdout)
    }
}

/// 0 → 1 between a and b, eased.
func ramp(_ t: Double, _ a: Double, _ b: Double) -> Double {
    let x = max(0, min(1, (t - a) / (b - a)))
    return x * x * (3 - 2 * x)
}

/// 0 → 1 with a little overshoot (springy pop).
func pop(_ t: Double, _ a: Double, _ len: Double = 0.45) -> Double {
    let x = max(0, min(1, (t - a) / len))
    let c = 1.9
    return x >= 1 ? 1 : 1 + (c + 1) * pow(x - 1, 3) + c * pow(x - 1, 2)
}

// MARK: - Picture

struct TrailerView: View {
    let t: Double
    let images: [String: NSImage]

    var body: some View {
        let T = Trailer.self
        ZStack {
            Color.black
            if t < T.welcomeStart + 0.6 {
                BrandIntro(t: min(t, BrandIntro.duration))
                    .opacity(1 - ramp(t, T.welcomeStart - 0.4, T.welcomeStart + 0.4))
            }
            if t >= T.welcomeStart - 0.4 {
                AquaBackground(t: t)
                    .opacity(ramp(t, T.welcomeStart - 0.4, T.welcomeStart + 0.4) * (1 - ramp(t, T.duration - 0.8, T.duration)))
                Particles(t: t)
                    .opacity(ramp(t, T.welcomeStart, T.welcomeStart + 1) * (1 - ramp(t, T.duration - 0.8, T.duration)))
            }
            if t >= T.welcomeStart - 0.2 && t < T.hypeStart + 0.2 {
                WelcomeCard(u: t - T.welcomeStart)
            }
            if t >= T.hypeStart - 0.05 && t < T.featuresStart + 0.1 {
                HypeCard(u: t - T.hypeStart)
            }
            ForEach(Array(T.scenes.enumerated()), id: \.offset) { i, s in
                let start = T.featuresStart + Double(i) * T.sceneLen
                if t >= start - 0.05 && t < start + T.sceneLen + 0.05 {
                    FeatureCard(scene: s, image: images[s.image], u: t - start, t: t, index: i)
                }
            }
            if t >= T.montageStart - 0.05 && t < T.endStart + 0.3 {
                Montage(u: t - T.montageStart, images: images)
            }
            if t >= T.endStart - 0.05 {
                EndCard(u: t - T.endStart)
                    .opacity(1 - ramp(t, T.duration - 0.8, T.duration))
            }
            // Flash on every cut.
            if let c = T.cuts.last(where: { $0 <= t }), t - c < 0.5, c > T.welcomeStart {
                Color.white.opacity(0.22 * exp(-(t - c) * 9)).blendMode(.plusLighter)
            }
            // Letterbox vignette
            RadialGradient(colors: [.clear, .black.opacity(0.55)], center: .center, startRadius: 600, endRadius: 1250)
                .allowsHitTesting(false)
        }
        .environment(\.colorScheme, .dark)
    }
}

private struct AquaBackground: View {
    let t: Double
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.01, green: 0.03, blue: 0.09), Color(red: 0.02, green: 0.09, blue: 0.19)],
                           startPoint: .top, endPoint: .bottom)
            ForEach(0..<5, id: \.self) { i in
                let d = Double(i)
                Circle()
                    .fill(RadialGradient(colors: [blob(i).opacity(0.55), .clear], center: .center, startRadius: 0, endRadius: 520))
                    .frame(width: 1100, height: 1100)
                    .offset(x: 700 * sin(t * (0.11 + d * 0.03) + d * 1.7), y: 380 * cos(t * (0.09 + d * 0.02) + d))
                    .blendMode(.plusLighter)
            }
            ForEach(0..<7, id: \.self) { i in
                let d = Double(i)
                Rectangle()
                    .fill(LinearGradient(colors: [.white.opacity(0.07), .clear], startPoint: .top, endPoint: .bottom))
                    .frame(width: 90 + 40 * sin(d), height: 1400)
                    .rotationEffect(.degrees(-18 + d * 6 + 3 * sin(t * 0.4 + d)))
                    .offset(x: -700 + d * 230 + 30 * sin(t * 0.3 + d * 2), y: -200)
                    .opacity(0.6 + 0.4 * sin(t * 0.7 + d * 1.3))
                    .blendMode(.plusLighter)
            }
        }
        .compositingGroup()
    }
    private func blob(_ i: Int) -> Color {
        [Color(red: 0.0, green: 0.55, blue: 0.85), Color(red: 0.25, green: 0.2, blue: 0.85), Color(red: 0.0, green: 0.75, blue: 0.7),
         Color(red: 0.6, green: 0.2, blue: 0.75), Color(red: 0.1, green: 0.4, blue: 0.95)][i % 5]
    }
}

/// Glowing bubbles drifting up, like light through water.
struct Particles: View {
    let t: Double
    var body: some View {
        Canvas { ctx, size in
            for i in 0..<70 {
                let seed = Double(i) * 12.9898
                let fx = (sin(seed) * 43758.5453).truncatingRemainder(dividingBy: 1)
                let x0 = abs(fx)
                let speed = 0.025 + 0.05 * abs(sin(seed * 1.7))
                let y = 1 - ((t * speed + abs(sin(seed * 3.1))).truncatingRemainder(dividingBy: 1.2)) + 0.1
                let x = x0 + 0.02 * sin(t * 0.8 + seed)
                let r = 1.5 + 4.5 * abs(sin(seed * 2.3))
                let a = 0.15 + 0.35 * (0.5 + 0.5 * sin(t * 2 + seed))
                let rect = CGRect(x: x * size.width - r, y: y * size.height - r, width: r * 2, height: r * 2)
                ctx.fill(Path(ellipseIn: rect.insetBy(dx: -r * 2, dy: -r * 2)), with: .color(Color(red: 0.5, green: 0.85, blue: 1).opacity(a * 0.18)))
                ctx.fill(Path(ellipseIn: rect), with: .color(.white.opacity(a)))
            }
        }
        .blendMode(.plusLighter)
    }
}

/// Words that rise and un-blur one after another.
struct KineticText: View {
    let text: String
    let u: Double
    let size: CGFloat
    var weight: Font.Weight = .heavy
    var gradient: [Color] = [.white, .white]
    var stagger = 0.07

    var body: some View {
        let words = text.split(separator: " ").map(String.init)
        HStack(spacing: size * 0.24) {
            ForEach(Array(words.enumerated()), id: \.offset) { i, w in
                let p = ramp(u, Double(i) * stagger, Double(i) * stagger + 0.45)
                Text(w)
                    .font(.system(size: size, weight: weight))
                    .foregroundStyle(LinearGradient(colors: gradient, startPoint: .leading, endPoint: .trailing))
                    .opacity(p)
                    .offset(y: size * 0.45 * (1 - p))
                    .blur(radius: 10 * (1 - p))
            }
        }
        .fixedSize()
    }
}

private struct WelcomeCard: View {
    let u: Double
    var body: some View {
        let write = ramp(u, 0.5, 2.5)
        let out = ramp(u, Trailer.welcomeLen - 0.5, Trailer.welcomeLen)
        VStack(spacing: 18) {
            Text("WELCOME TO")
                .font(.system(size: 30, weight: .semibold))
                .tracking(14 + 6 * ramp(u, 0, 3))
                .foregroundStyle(.white.opacity(0.85))
                .opacity(ramp(u, 0.0, 0.6))
                .offset(y: 16 * (1 - ramp(u, 0.0, 0.7)))
            ZStack {
                LetteringShape("Aquatic", size: 220)
                    .trim(from: 0, to: write)
                    .stroke(LinearGradient(colors: [.white, Color(red: 0.5, green: 0.9, blue: 1)], startPoint: .leading, endPoint: .trailing),
                            style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                LetteringShape("Aquatic", size: 220)
                    .fill(LinearGradient(colors: [.white, Color(red: 0.55, green: 0.92, blue: 1)], startPoint: .leading, endPoint: .trailing))
                    .opacity(ramp(u, 2.1, 2.8))
                // Shine sweeping across the lettering
                LetteringShape("Aquatic", size: 220)
                    .fill(LinearGradient(colors: [.clear, .white.opacity(0.9), .clear],
                                         startPoint: UnitPoint(x: -0.4 + 1.8 * ramp(u, 2.8, 3.8), y: 0),
                                         endPoint: UnitPoint(x: -0.1 + 1.8 * ramp(u, 2.8, 3.8), y: 1)))
                    .opacity(ramp(u, 2.8, 2.9) * (1 - ramp(u, 3.7, 3.9)))
                    .blendMode(.plusLighter)
            }
            .frame(width: 900, height: 260)
            .shadow(color: Color(red: 0.3, green: 0.8, blue: 1).opacity(0.6 * ramp(u, 2.2, 3.0)), radius: 30)
            KineticText(text: "Aries Dynamic Island 2.0", u: u - 2.7, size: 34, weight: .bold)
        }
        .scaleEffect(1 + 0.05 * u / Trailer.welcomeLen + 0.08 * out)
        .blur(radius: 14 * out)
        .opacity(1 - out)
    }
}

/// "The biggest update yet." on the beat, then a huge 2.0 slam.
private struct HypeCard: View {
    let u: Double
    var body: some View {
        let b = Trailer.beat
        let words = ["The", "biggest", "Aries", "update", "yet."]
        let slam = u - Double(words.count) * b - 0.1
        ZStack {
            if slam < 0.2 {
                HStack(spacing: 26) {
                    ForEach(Array(words.enumerated()), id: \.offset) { i, w in
                        let p = pop(u, Double(i) * b, 0.35)
                        Text(w)
                            .font(.system(size: 92, weight: .black))
                            .foregroundStyle(i == 1 ? AnyShapeStyle(LinearGradient(colors: [.cyan, .white], startPoint: .leading, endPoint: .trailing)) : AnyShapeStyle(.white))
                            .scaleEffect(0.4 + 0.6 * p)
                            .opacity(min(1, p * 1.5))
                    }
                }
                .opacity(1 - ramp(slam, -0.1, 0.15))
                .scaleEffect(1 + 0.04 * u)
            }
            if slam > -0.05 {
                let p = pop(slam, 0, 0.5)
                ZStack {
                    Text("2.0")
                        .font(.system(size: 420, weight: .black, design: .rounded))
                        .foregroundStyle(LinearGradient(colors: [.white, Color(red: 0.45, green: 0.9, blue: 1), Color(red: 0.3, green: 0.4, blue: 1)],
                                                        startPoint: .topLeading, endPoint: .bottomTrailing))
                        .shadow(color: Color(red: 0.3, green: 0.8, blue: 1).opacity(0.8), radius: 60)
                    Text("2.0")
                        .font(.system(size: 420, weight: .black, design: .rounded))
                        .foregroundStyle(LinearGradient(colors: [.clear, .white.opacity(0.9), .clear],
                                                        startPoint: UnitPoint(x: -0.5 + 2 * ramp(slam, 0.3, 1.2), y: 0),
                                                        endPoint: UnitPoint(x: -0.2 + 2 * ramp(slam, 0.3, 1.2), y: 1)))
                        .blendMode(.plusLighter)
                }
                .scaleEffect(2.2 - 1.2 * p + 0.05 * max(0, slam))
                .opacity(min(1, slam * 6) * (1 - ramp(u, Trailer.hypeLen - 0.25, Trailer.hypeLen)))
                .blur(radius: 18 * ramp(u, Trailer.hypeLen - 0.25, Trailer.hypeLen))
            }
        }
    }
}

private struct FeatureCard: View {
    let scene: Trailer.Scene
    let image: NSImage?
    let u: Double
    let t: Double
    let index: Int

    var body: some View {
        let L = Trailer.sceneLen
        let inP = ramp(u, 0, 0.5)
        let out = ramp(u, L - 0.3, L)
        let tall = (image.map { $0.size.height > $0.size.width }) ?? false
        let side: Double = index.isMultiple(of: 2) ? 1 : -1
        Group {
            if tall {
                HStack(spacing: 110) {
                    titles(alignment: .leading)
                    shot(maxW: 520, maxH: 880, side: side)
                }
            } else {
                VStack(spacing: 40) {
                    titles(alignment: .center)
                    shot(maxW: 1340, maxH: 660, side: side)
                }
            }
        }
        // Slow camera push and drift
        .scaleEffect(1 + 0.035 * u / L)
        .offset(x: side * 70 * (1 - inP) - side * 60 * out)
        .opacity(inP * (1 - out))
        .blur(radius: 12 * out)
    }

    private func titles(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 12) {
            // Feature number, like a chapter marker
            Text(String(format: "%02d", index + 1))
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundStyle(scene.tint.opacity(0.9))
                .tracking(4)
                .opacity(ramp(u, 0, 0.4))
            KineticText(text: scene.title, u: u - 0.08, size: 64, gradient: [.white, scene.tint.opacity(0.95)])
            Text(scene.sub)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
                .opacity(ramp(u, 0.45, 0.95))
                .offset(y: 18 * (1 - ramp(u, 0.45, 1.0)))
        }
        .multilineTextAlignment(alignment == .center ? .center : .leading)
    }

    @ViewBuilder
    private func shot(maxW: CGFloat, maxH: CGFloat, side: Double) -> some View {
        if let img = image {
            let s = img.size
            let k = min(maxW / s.width, maxH / s.height)
            let w = s.width * k, h = s.height * k
            let enter = ramp(u, 0.1, 0.85)
            ZStack {
                Image(nsImage: img).resizable().interpolation(.high)
                    .frame(width: w, height: h)
                    .scaleEffect(1.0 + 0.05 * u / Trailer.sceneLen)
                // Light sweep across the glass
                LinearGradient(colors: [.clear, .white.opacity(0.22), .clear],
                               startPoint: UnitPoint(x: -0.6 + 2.2 * ramp(u, 0.6, 1.9), y: 0),
                               endPoint: UnitPoint(x: -0.2 + 2.2 * ramp(u, 0.6, 1.9), y: 1))
                    .blendMode(.plusLighter)
            }
            .frame(width: w, height: h)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(LinearGradient(colors: [.white.opacity(0.45), scene.tint.opacity(0.4), .white.opacity(0.08)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5))
            .shadow(color: scene.tint.opacity(0.5), radius: 60)
            .shadow(color: .black.opacity(0.55), radius: 30, y: 24)
            // 3D: swings in, then slowly turns
            .rotation3DEffect(.degrees(side * (24 * (1 - enter) - 5 + 7 * u / Trailer.sceneLen)), axis: (x: 0.15, y: 1, z: 0),
                              perspective: 0.55)
            .rotation3DEffect(.degrees(10 * (1 - enter)), axis: (x: 1, y: 0, z: 0), perspective: 0.55)
            .scaleEffect(0.86 + 0.14 * enter)
            .offset(y: 60 * (1 - enter) + 6 * sin(t * 1.4))
            .opacity(min(1, enter * 1.6))
        }
    }
}

/// "And so much more": a moving wall of every screen, with feature tags popping in on the beat.
private struct Montage: View {
    let u: Double
    let images: [String: NSImage]

    var body: some View {
        let inP = ramp(u, 0, 0.6), out = ramp(u, Trailer.montageLen - 0.4, Trailer.montageLen)
        let names = Trailer.wall
        ZStack {
            VStack(spacing: 26) {
                ForEach(0..<4, id: \.self) { row in
                    let dir: Double = row.isMultiple(of: 2) ? -1 : 1
                    HStack(spacing: 26) {
                        ForEach(0..<10, id: \.self) { k in
                            let name = names[(row * 5 + k) % names.count]
                            if let img = images["wall:" + name] {
                                let h: CGFloat = 230
                                Image(nsImage: img).resizable().interpolation(.high)
                                    .frame(width: min(560, img.size.width * h / img.size.height), height: h)
                                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.15), lineWidth: 1))
                            }
                        }
                    }
                    .fixedSize()
                    .offset(x: dir * (u * 140 + 300) - 400)
                }
            }
            .rotationEffect(.degrees(-11))
            .scaleEffect(1.25 - 0.08 * u / Trailer.montageLen)
            .opacity(0.5 * inP)
            .blur(radius: 1.5)

            // Dark wash so the title pops
            RadialGradient(colors: [.black.opacity(0.75), .black.opacity(0.1)], center: .center, startRadius: 120, endRadius: 760)

            // Tags on the beat
            ForEach(Array(Trailer.chips.enumerated()), id: \.offset) { i, c in
                FeatureChip(icon: c.0, label: c.1, index: i, u: u)
            }

            VStack(spacing: 10) {
                KineticText(text: "And so much more.", u: u - 0.2, size: 96, weight: .black,
                            gradient: [.white, Color(red: 0.55, green: 0.9, blue: 1)], stagger: 0.12)
                Text("\(Trailer.chips.count + Trailer.scenes.count)+ features, free.")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .opacity(ramp(u, 1.2, 1.8))
            }
        }
        .opacity(1 - out)
        .blur(radius: 14 * out)
    }
}

private struct FeatureChip: View {
    let icon: String
    let label: String
    let index: Int
    let u: Double

    var body: some View {
        let appear = 0.9 + Double(index) * Trailer.beat * 0.68
        let p = pop(u, appear, 0.4)
        let ang = Double(index) * 2.399963          // golden angle spreads them evenly
        let rad = 330 + 120 * Double(index % 3)
        let y0 = sin(ang) * rad * 0.8
        let y = (y0 < 0 ? min(-170, y0) : max(170, y0)) + 6 * cos(u * 1.3 + Double(index))
        let x = cos(ang) * rad * 1.5 + 8 * sin(u + Double(index))
        HStack(spacing: 9) {
            Image(systemName: icon).font(.system(size: 20, weight: .bold))
            Text(label).font(.system(size: 22, weight: .bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18).frame(height: 50)
        .background(Capsule().fill(Color(red: 0.2, green: 0.6, blue: 1).opacity(0.28)))
        .background(Capsule().fill(.black.opacity(0.35)))
        .overlay(Capsule().stroke(.white.opacity(0.35), lineWidth: 1))
        .shadow(color: Color(red: 0.3, green: 0.8, blue: 1).opacity(0.5), radius: 16)
        .scaleEffect(0.3 + 0.7 * p)
        .opacity(u > appear ? min(1, p * 2) : 0)
        .offset(x: x, y: y)
    }
}

private struct EndCard: View {
    let u: Double
    var body: some View {
        VStack(spacing: 22) {
            ZStack {
                ForEach(0..<3, id: \.self) { r in
                    Circle().stroke(Color(red: 0.5, green: 0.9, blue: 1).opacity(0.35 * (1 - ramp(u, Double(r) * 0.4, Double(r) * 0.4 + 2))), lineWidth: 2)
                        .frame(width: 200 + 600 * ramp(u, Double(r) * 0.4, Double(r) * 0.4 + 2),
                               height: 200 + 600 * ramp(u, Double(r) * 0.4, Double(r) * 0.4 + 2))
                }
                Circle().fill(RadialGradient(colors: [Color(red: 0.4, green: 0.85, blue: 1).opacity(0.5), .clear],
                                             center: .center, startRadius: 0, endRadius: 260))
                    .frame(width: 520, height: 520)
                    .scaleEffect(0.8 + 0.25 * ramp(u, 0, 1.4))
                    .opacity(ramp(u, 0, 0.8))
                if let logo = Brand.appLogo {
                    Image(nsImage: logo).resizable().interpolation(.high).scaledToFit()
                        .frame(width: 300, height: 300)
                        .blendMode(.screen)
                        .scaleEffect(0.6 + 0.4 * pop(u, 0, 0.8))
                        .rotation3DEffect(.degrees(30 * (1 - ramp(u, 0, 1.2))), axis: (x: 0, y: 1, z: 0))
                        .opacity(ramp(u, 0, 0.5))
                }
            }
            .frame(height: 320)
            KineticText(text: "Aries Dynamic Island", u: u - 0.6, size: 78)
            HStack(spacing: 14) {
                Text("2.0").font(.system(size: 40, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.85))
                LetteringShape("Aquatic", size: 120)
                    .trim(from: 0, to: ramp(u, 1.0, 2.0))
                    .stroke(.white, lineWidth: 1.5)
                    .frame(width: 230, height: 76)
                    .overlay(LetteringShape("Aquatic", size: 120)
                        .fill(LinearGradient(colors: [.white, Color(red: 0.55, green: 0.92, blue: 1)], startPoint: .leading, endPoint: .trailing))
                        .opacity(ramp(u, 1.8, 2.3)))
            }
            .opacity(ramp(u, 1.0, 1.3))
            Text("Free download on GitHub")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.black)
                .padding(.horizontal, 34).frame(height: 62)
                .background(Capsule().fill(.white))
                .shadow(color: Color(red: 0.4, green: 0.85, blue: 1).opacity(0.7 + 0.3 * sin(u * 3)), radius: 28)
                .scaleEffect(0.6 + 0.4 * pop(u, 2.2, 0.5))
                .opacity(ramp(u, 2.2, 2.5))
                .padding(.top, 10)
            Text("A  MAXX  FORGE  STUDIO  PRODUCT")
                .font(.system(size: 16, weight: .semibold))
                .tracking(4 + 2 * ramp(u, 2.8, 5))
                .foregroundStyle(.white.opacity(0.55))
                .opacity(ramp(u, 2.8, 3.4))
                .padding(.top, 16)
        }
        .scaleEffect(1 + 0.03 * u / Trailer.endLen)
    }
}

// MARK: - Sound (original, synthesized)

enum TrailerAudio {
    static let rate = 44100.0

    static func render(to url: URL, duration: Double) throws {
        let n = Int(duration * rate)
        var L = [Float](repeating: 0, count: n), R = [Float](repeating: 0, count: n)
        let featuresStart = Trailer.hypeStart, endStart = Trailer.endStart

        // Chords: Fmaj7 – Am7 – Dm9 – Bbmaj7, two bars each at 120 bpm.
        let chords: [[Double]] = [
            [87.31, 174.61, 220.00, 261.63, 329.63],
            [110.00, 220.00, 261.63, 329.63, 392.00],
            [73.42, 146.83, 174.61, 220.00, 261.63, 329.63],
            [58.27, 174.61, 220.00, 233.08, 293.66],
        ]
        let chordLen = 4.0
        func chordAt(_ t: Double) -> [Double] { chords[Int(t / chordLen) % chords.count] }

        // Pads
        for i in 0..<n {
            let t = Double(i) / rate
            let ci = Int(t / chordLen)
            let local = t - Double(ci) * chordLen
            let c = chords[ci % chords.count]
            let env = min(1, local / 1.2) * (local > chordLen - 0.3 ? max(0, (chordLen - local) / 0.3) * 0.6 + 0.4 : 1)
            var s = 0.0
            for (k, f) in c.enumerated() {
                let det = 1 + 0.0025 * Double(k % 2 == 0 ? 1 : -1)
                s += (sin(2 * .pi * f * t) + 0.35 * sin(2 * .pi * f * 2 * det * t) + 0.12 * sin(2 * .pi * f * 3 * t)) / Double(c.count)
            }
            let master = 0.20 * (t < featuresStart ? 0.75 : 1.0) * fadeOut(t, duration)
            let v = Float(s * env * master)
            L[i] += v; R[i] += v * 0.97
        }

        // Kick, hats and arpeggio once the features start
        let beat = 0.5
        var bt = featuresStart
        var step = 0
        while bt < endStart {
            add(&L, &R, at: bt, len: 0.4, gain: 0.55) { x in sin(2 * .pi * (45 + 75 * exp(-x * 30)) * x) * exp(-x * 9) }
            add(&L, &R, at: bt + beat / 2, len: 0.06, gain: 0.05, pan: 0.3) { x in (Double.random(in: -1...1)) * exp(-x * 60) }
            // Arpeggio: chord tones, two octaves up, eighth notes.
            let c = chordAt(bt)
            for half in 0..<2 {
                let f = c[1 + (step * 2 + half) % (c.count - 1)] * 2
                add(&L, &R, at: bt + Double(half) * beat / 2, len: 0.45, gain: 0.07, pan: half == 0 ? -0.35 : 0.35) { x in
                    (sin(2 * .pi * f * x) + 0.3 * sin(2 * .pi * f * 2 * x)) * exp(-x * 7)
                }
            }
            bt += beat; step += 1
        }

        // Whooshes into each cut, and a low hit on it
        for c in Trailer.cuts where c < duration - 0.5 {
            var lp = 0.0
            add(&L, &R, at: c - 0.7, len: 0.9, gain: 0.22) { x in
                let a = min(1, x / 0.7) * (x > 0.7 ? exp(-(x - 0.7) * 18) : 1)
                let cutoff = 0.02 + 0.25 * min(1, x / 0.7)
                lp += cutoff * (Double.random(in: -1...1) - lp)
                return lp * a * a
            }
            add(&L, &R, at: c, len: 1.2, gain: 0.35) { x in sin(2 * .pi * (38 + 40 * exp(-x * 12)) * x) * exp(-x * 3.5) }
        }

        // Final chord for the end card
        let fin: [Double] = [87.31, 174.61, 261.63, 329.63, 440.0, 523.25]
        add(&L, &R, at: endStart, len: Trailer.endLen, gain: 0.22) { x in
            fin.reduce(0) { $0 + sin(2 * .pi * $1 * x) } / Double(fin.count) * min(1, x / 0.05) * exp(-x * 0.45)
        }

        // Soft-clip and write
        let fmt = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
        let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(n))!
        buf.frameLength = AVAudioFrameCount(n)
        for i in 0..<n {
            buf.floatChannelData![0][i] = tanhf(L[i] * 1.2) * 0.9
            buf.floatChannelData![1][i] = tanhf(R[i] * 1.2) * 0.9
        }
        try? FileManager.default.removeItem(at: url)
        let file = try AVAudioFile(forWriting: url, settings: fmt.settings)
        try file.write(from: buf)
    }

    private static func fadeOut(_ t: Double, _ d: Double) -> Double { t > d - 1.2 ? max(0, (d - t) / 1.2) : 1 }

    private static func add(_ L: inout [Float], _ R: inout [Float], at t0: Double, len: Double, gain: Double, pan: Double = 0,
                            _ f: (Double) -> Double) {
        let s0 = max(0, Int(t0 * rate)), s1 = min(L.count, Int((t0 + len) * rate))
        guard s1 > s0 else { return }
        let gl = Float(gain * (1 - max(0, pan))), gr = Float(gain * (1 + min(0, pan)))
        for i in s0..<s1 {
            let v = Float(f(Double(i) / rate - t0))
            L[i] += v * gl; R[i] += v * gr
        }
    }
}

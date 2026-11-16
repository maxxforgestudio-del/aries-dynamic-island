import AppKit
import SwiftUI
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

/// The Aries brand intro, in the spirit of Apple's "hello":
/// "Aries Dynamic Island" writes itself in cursive, sweeps into the chrome "A",
/// the orbit and sparkle draw in, and it lands on the full logo.
///
/// Everything is a pure function of `t` (seconds), so the same view plays live in the
/// app and renders frame-perfect into video files.
struct BrandIntro: View {
    static let duration = 9.0

    var t: Double

    private static let lettering = LetteringShape("Aries Dynamic Island")

    var body: some View {
        GeometryReader { g in
            let size = g.size
            let side = min(size.width, size.height * 1.05)
            let logoRect = CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side)
            ZStack {
                Color.black
                starfield(size)
                RadialGradient(colors: [Color.white.opacity(0.08 * ease(clamp(t / 2))), .clear],
                               center: .center, startRadius: 0, endRadius: max(size.width, size.height) * 0.55)

                // 1 — cursive writing
                writing(size)

                // 2 — the "A" and orbit draw themselves where the logo's A sits
                mark(logoRect)

                // 3 — the real logo artwork takes over
                if let logo = Brand.appLogo {
                    let reveal = ease(clamp((t - 5.6) / 0.9))
                    Image(nsImage: logo)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: side, height: side)
                        .position(x: logoRect.midX, y: logoRect.midY)
                        .opacity(reveal)
                        .scaleEffect(1.04 - 0.04 * ease(clamp((t - 5.6) / 2.4)))
                        .blendMode(.screen)   // the artwork's black background disappears into the scene
                        .overlay(glint(logo: logo, rect: logoRect))
                }

                // 4 — sign-off
                signOff(size)
            }
            .frame(width: size.width, height: size.height)
        }
        .environment(\.colorScheme, .dark)
    }

    // MARK: Phases

    private func writing(_ size: CGSize) -> some View {
        let w = min(size.width * 0.82, size.height * 2.6)
        let h = w * 0.26
        let draw = ease(clamp((t - 0.3) / 3.0))
        let fill = ease(clamp((t - 3.0) / 0.6))
        // Sweep: the words shrink and drift up into the A, then dissolve.
        let sweep = easeIn(clamp((t - 3.9) / 1.0))
        let silver = LinearGradient(colors: [.white, Color(white: 0.62), .white, Color(white: 0.75)],
                                    startPoint: .leading, endPoint: .trailing)
        return ZStack {
            Self.lettering
                .trim(from: 0, to: draw)
                .stroke(silver, style: StrokeStyle(lineWidth: max(1.6, w / 520), lineCap: .round, lineJoin: .round))
                .opacity(1 - fill)
            Self.lettering
                .fill(silver)
                .opacity(fill)
                .shadow(color: .white.opacity(0.35 * fill), radius: w / 60)
        }
        .frame(width: w, height: h)
        .position(x: size.width / 2, y: size.height / 2)
        .scaleEffect(1 - 0.72 * sweep)
        .offset(y: -size.height * 0.05 * sweep)
        .blur(radius: 14 * sweep)
        .opacity(1 - sweep)
    }

    private func mark(_ r: CGRect) -> some View {
        let k = r.width / 1254
        let tf = CGAffineTransform(translationX: r.minX, y: r.minY).scaledBy(x: k, y: k)
        let a = ease(clamp((t - 4.1) / 1.4))
        let orbit = ease(clamp((t - 4.5) / 1.3))
        let handoff = 1 - ease(clamp((t - 5.8) / 0.7))
        let chrome = LinearGradient(colors: [.white, Color(white: 0.55), .white, Color(white: 0.7), .white],
                                    startPoint: .topLeading, endPoint: .bottomTrailing)
        return ZStack {
            OrbitPath().transform(tf).trim(from: 0, to: orbit)
                .stroke(chrome, style: StrokeStyle(lineWidth: 7 * k, lineCap: .round))
            APath().transform(tf).trim(from: 0, to: a)
                .stroke(chrome, style: StrokeStyle(lineWidth: 16 * k, lineCap: .round, lineJoin: .round))
            sparkle(at: CGPoint(x: r.minX + 905 * k, y: r.minY + 518 * k), size: 120 * k,
                    p: ease(clamp((t - 5.3) / 0.6)))
        }
        .shadow(color: .white.opacity(0.5), radius: 10 * k)
        .opacity(handoff)
    }

    private func sparkle(at p: CGPoint, size s: CGFloat, p prog: Double) -> some View {
        let twinkle = 1 + 0.25 * sin(t * 9)
        return SparkleShape()
            .fill(.white)
            .frame(width: s, height: s)
            .scaleEffect(prog * twinkle)
            .rotationEffect(.degrees(45 * (1 - prog)))
            .shadow(color: .white, radius: s * 0.15 * prog)
            .position(p)
            .opacity(prog)
    }

    /// A band of light sweeping across the chrome, clipped to the logo artwork.
    private func glint(logo: NSImage, rect: CGRect) -> some View {
        let p = easeInOut(clamp((t - 6.5) / 1.3))
        return GeometryReader { g in
            LinearGradient(colors: [.clear, .white.opacity(0.75), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: rect.width * 0.22, height: rect.height * 1.4)
                .rotationEffect(.degrees(20))
                .position(x: rect.minX + rect.width * (-0.2 + 1.4 * p), y: rect.midY)
                .blendMode(.plusLighter)
                .mask(
                    Image(nsImage: logo).resizable().frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .luminanceToAlpha()
                )
                .opacity(p > 0 && p < 1 ? 1 : 0)
                .frame(width: g.size.width, height: g.size.height)
        }
    }

    private func signOff(_ size: CGSize) -> some View {
        let p = ease(clamp((t - 7.3) / 0.8))
        let s = min(size.width, size.height)
        return HStack(spacing: s * 0.018) {
            if let owl = Brand.logo {
                Image(nsImage: owl).resizable().interpolation(.high).scaledToFit().frame(width: s * 0.07, height: s * 0.07)
            }
            Text("A MAXX FORGE STUDIO PRODUCT")
                .font(.system(size: s * 0.022, weight: .heavy, design: .rounded))
                .tracking(s * 0.004)
                .foregroundStyle(.white.opacity(0.8))
        }
        .opacity(p)
        .offset(y: 12 * (1 - p))
        .position(x: size.width / 2, y: size.height - s * 0.075)
    }

    private func starfield(_ size: CGSize) -> some View {
        Canvas { ctx, sz in
            var rng = SeededRandom(seed: 7)
            for _ in 0..<90 {
                let x = rng.next() * sz.width, y = rng.next() * sz.height
                let r = 0.5 + rng.next() * 1.3
                let phase = rng.next() * 6.28
                let a = 0.15 + 0.35 * (0.5 + 0.5 * sin(t * 1.6 + phase))
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y - t * 4, width: r, height: r)), with: .color(.white.opacity(a)))
            }
        }
        .opacity(0.8)
    }

    // MARK: Easing

    private func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
    private func ease(_ x: Double) -> Double { 1 - pow(1 - x, 3) }          // ease-out cubic
    private func easeIn(_ x: Double) -> Double { x * x * x }
    private func easeInOut(_ x: Double) -> Double { x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2 }
}

private struct SeededRandom {
    var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 }
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(1 << 53)
    }
}

/// The cursive "A" from the Aries logo, traced as strokes (in the logo's 1254-pt space).
private struct APath: Shape {
    func path(in _: CGRect) -> Path {
        var p = Path()
        // Left curl sweeping up the long diagonal to the apex.
        p.move(to: CGPoint(x: 560, y: 600))
        p.addCurve(to: CGPoint(x: 270, y: 735), control1: CGPoint(x: 430, y: 610), control2: CGPoint(x: 250, y: 680))
        p.addCurve(to: CGPoint(x: 470, y: 690), control1: CGPoint(x: 290, y: 790), control2: CGPoint(x: 400, y: 750))
        p.addCurve(to: CGPoint(x: 948, y: 262), control1: CGPoint(x: 620, y: 560), control2: CGPoint(x: 820, y: 330))
        // Right leg falling from the apex with a little hook.
        p.addCurve(to: CGPoint(x: 778, y: 650), control1: CGPoint(x: 880, y: 340), control2: CGPoint(x: 770, y: 520))
        p.addCurve(to: CGPoint(x: 838, y: 718), control1: CGPoint(x: 782, y: 700), control2: CGPoint(x: 810, y: 728))
        // Crossbar swoosh.
        p.move(to: CGPoint(x: 352, y: 606))
        p.addCurve(to: CGPoint(x: 866, y: 568), control1: CGPoint(x: 500, y: 560), control2: CGPoint(x: 720, y: 520))
        return p
    }
}

/// The orbit ellipse around the A.
private struct OrbitPath: Shape {
    func path(in _: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: 638, y: 535), rx = 425.0, ry = 140.0, rot = 9.0 * .pi / 180
        let steps = 160
        for i in 0...steps {
            let a = -Double.pi * 0.95 + Double(i) / Double(steps) * 2 * .pi * 0.97
            let x = rx * cos(a), y = ry * sin(a)
            let pt = CGPoint(x: c.x + x * cos(rot) - y * sin(rot), y: c.y + x * sin(rot) + y * cos(rot))
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        return p
    }
}

/// Four-point star ✦.
struct SparkleShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: r.midX, y: r.midY), o = r.width / 2, i = r.width * 0.09
        p.move(to: CGPoint(x: c.x, y: c.y - o))
        p.addQuadCurve(to: CGPoint(x: c.x + o, y: c.y), control: CGPoint(x: c.x + i, y: c.y - i))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + o), control: CGPoint(x: c.x + i, y: c.y + i))
        p.addQuadCurve(to: CGPoint(x: c.x - o, y: c.y), control: CGPoint(x: c.x - i, y: c.y + i))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - o), control: CGPoint(x: c.x - i, y: c.y - i))
        return p
    }
}

/// Plays the intro live (in the Welcome window).
struct BrandIntroPlayer: View {
    var onFinished: () -> Void = {}
    @ViewState private var start = Date()
    @ViewState private var done = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: done)) { tl in
            let t = A11y.reduceMotion ? BrandIntro.duration : tl.date.timeIntervalSince(start)
            BrandIntro(t: min(t, BrandIntro.duration))
                .onChange(of: t >= BrandIntro.duration - 0.6) { _, finished in
                    if finished && !done { done = true; onFinished() }
                }
        }
        .onAppear {
            start = Date()
            if A11y.reduceMotion { DispatchQueue.main.async { done = true; onFinished() } }
        }
    }
}

// MARK: - Video export

enum IntroExporter {
    /// Renders the intro to an H.264 MP4, frame by frame.
    @MainActor static func renderVideo(to url: URL, size: CGSize, fps: Int = 60, duration durationIn: Double? = nil,
                                       frame makeFrame: ((Double, CGSize) -> CGImage?)? = nil,
                                       progress: ((Double) -> Void)? = nil) throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: Int(size.width * size.height * 8),
                                              AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel],
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let duration = durationIn ?? BrandIntro.duration
        let frames = Int(duration * Double(fps))
        for f in 0...frames {
            let t = Double(f) / Double(fps)
            guard let cg = autoreleasepool(invoking: { makeFrame?(t, size) ?? frame(t: t, size: size) }) else { continue }
            if f % fps == 0 { progress?(t / duration) }
            while !input.isReadyForMoreMediaData { RunLoop.current.run(until: Date().addingTimeInterval(0.005)) }
            if let pb = pixelBuffer(from: cg, pool: adaptor.pixelBufferPool) {
                adaptor.append(pb, withPresentationTime: CMTime(value: CMTimeValue(f), timescale: CMTimeScale(fps)))
            }
        }
        input.markAsFinished()
        let sem = DispatchSemaphore(value: 0)
        writer.finishWriting { sem.signal() }
        while sem.wait(timeout: .now()) == .timedOut { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        if writer.status != .completed { throw writer.error ?? NSError(domain: "Aries", code: 2) }
    }

    /// A small looping GIF (for the README).
    @MainActor static func renderGIF(to url: URL, size: CGSize, fps: Int = 15) throws {
        try? FileManager.default.removeItem(at: url)
        let frames = Int(BrandIntro.duration * Double(fps))
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames + 1, nil)
        else { throw NSError(domain: "Aries", code: 3) }
        CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for f in 0...frames {
            let t = Double(f) / Double(fps)
            guard let cg = frame(t: t, size: size) else { continue }
            let delay = f == frames ? 2.5 : 1.0 / Double(fps)
            CGImageDestinationAddImage(dest, cg, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary)
        }
        if !CGImageDestinationFinalize(dest) { throw NSError(domain: "Aries", code: 4) }
    }

    @MainActor static func frame(t: Double, size: CGSize) -> CGImage? {
        let r = ImageRenderer(content: BrandIntro(t: t).frame(width: size.width, height: size.height))
        r.scale = 1
        r.proposedSize = ProposedViewSize(size)
        return r.cgImage
    }

    private static func pixelBuffer(from image: CGImage, pool: CVPixelBufferPool?) -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        if let pool { CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb) }
        guard let buffer = pb else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: image.width, height: image.height,
                                  bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return buffer
    }
}

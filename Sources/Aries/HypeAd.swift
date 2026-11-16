import AppKit
import SwiftUI

/// A vertical hype edit for Aries 2.0, cut to the beat of loveboy1939's "USER_ERROR_remix"
/// (song 140.0 s → end, 161.5 bpm). Real screen recordings and app frames, hard cuts,
/// zoom punches, flashes and big text slams.
/// Run: `Aries --render-hype <outDir> <workDir>` where workDir holds snap/, footage/, fn3/, ff2/.
enum Hype {
    static let size = CGSize(width: 1920, height: 1080)
    static let beat = 60.0 / 161.5
    static let first = 0.287          // first beat of the excerpt
    static var duration: Double { 44.85 + shift * beat + endHold }
    /// Extra seconds the end card stays up after the song ends, so people can read and scan it.
    static let endHold = 2.4
    static var available: Double { B(108) }
    static let aqua = Color(red: 0.32, green: 0.86, blue: 1.0)
    /// Extra beats at the start for the MacBook intro (the song starts 16 beats earlier).
    static let shift = 16.0
    static let songStart = 140.0 - 16 * 60.0 / 161.5
    /// Beat k of the main edit (after the MacBook intro).
    static func B(_ k: Double) -> Double { first + (k + shift) * beat }
    /// Beat k counted from the very start of the video.
    static func Braw(_ k: Double) -> Double { first + k * beat }
    static var drop: Double { B(58) }  // song 161.83 s
    static var breakStart: Double { 19.1 + shift * beat }
    static var endCard: Double { B(110) }

    enum Src {
        case live(String, Double)    // frames dir, start time in that recording
        case still(String)
        case none
    }

    struct Seg {
        let from: Double, to: Double   // beats
        let src: Src
        let text: String
        var island = false             // wide island shot: float over a blurred copy
        var zoom: CGFloat = 1
        var focus = UnitPoint.center
    }

    static let wideStills: Set<String> = ["02-music", "03-music-queue", "04-music-devices", "06-notes", "07-shelf",
                                          "08b-tools", "09-call-incoming", "12-song-toast", "05-home"]

    static let segs: [Seg] = {
        func L(_ d: String, _ t: Double) -> Src { .live(d, t) }
        var s: [Seg] = []
        // Before the drop: one feature per shot, nothing repeated
        let intro: [(Double, Double, Src, String)] = [
            (8, 12, L("upd6", 0.6), "MEET ARIES."),
            (12, 16, L("upd6", 9.0), "WELCOME TO AQUATIC."),
            (16, 20, L("fn4", 1.2), "YOUR MUSIC, LIVE."),
            (20, 24, L("ff6", 0.4), "FULL SCREEN."),
            (24, 28, L("ff6", 5.0), "SPIN IT ON VINYL."),
            (28, 30, .still("15-lyrics"), "EVERY WORD, IN SYNC."),
            (30, 32, .still("15c-karaoke"), "SING IT."),
            (32, 34, L("wn6", 0.4), "WHAT'S NEW."),
            (34, 36, L("set6", 1.2), "PICK YOUR GLASS."),
            (36, 38, L("isl", 3.6), "CLASSIC. CRYSTAL. AQUATIC."),
            (38, 40, L("fn4", 5.1), "LIKE IT."),
            (40, 42, .still("09-call-incoming"), "NEVER MISS A CALL."),
            (42, 44, L("fn4", 11.6), "FOCUS MODES."),
            (44, 46, L("fn4", 14.6), "TOOLS."),
            (46, 48, .still("15d-widgets"), "WIDGETS."),
            (48, 50.7, L("isl", 7.1), "CHARGING."),
        ]
        for i in intro { s.append(Seg(from: i.0, to: i.1, src: i.2, text: i.3)) }
        // After the drop: a new feature every two beats
        let montage: [(Src, String)] = [
            (L("set6", 6.0), "LOCK SCREEN WIDGETS"), (L("sp6", 1.2), "SPOTIFY ARTISTS"),
            (L("isl", 9.1), "UNLOCK GREETING"), (L("set6", 9.3), "POPUPS"),
            (L("fn4", 7.6), "LIVE ACTIVITIES"), (L("isl", 12.6), "LIVE SCORES"),
            (L("set6", 10.0), "SHORTCUTS"), (L("isl", 17.0), "FILE SHELF"),
            (L("sp6", 5.8), "FULL ALBUMS"), (L("sp6", 10.2), "UP NEXT"),
            (L("fn4", 17.2), "STOPWATCH"), (L("fn4", 23.1), "AIRPODS"),
            (L("set6", 7.3), "LYRICS STYLES"), (L("fn4", 21.1), "CAPS LOCK"),
            (.still("06-notes"), "NOTES & TO-DOS"), (L("set6", 8.0), "FACETIME & CALLS"),
            (L("isl", 14.8), "FLIGHTS"), (L("set6", 11.3), "AUTO UPDATES"),
            (.still("14-volume"), "VOLUME"), (L("set6", 13.0), "MAXX FORGE STUDIO"),
        ]
        for (i, m) in montage.enumerated() { s.append(Seg(from: 62 + Double(i) * 2, to: 64 + Double(i) * 2, src: m.0, text: m.1)) }
        // Climax: one cut per beat
        let climax: [(Src, String)] = [
            (L("upd6", 6.4), "YOUR"), (L("ff6", 8.2), "NOTCH."), (.still("16-player"), "BUT"),
            (L("fn4", 2.6), "BETTER."), (L("upd6", 11.6), "ARIES"), (L("isl", 2.0), "2.0"),
        ]
        for (i, c) in climax.enumerated() { s.append(Seg(from: 102 + Double(i), to: 103 + Double(i), src: c.0, text: c.1)) }
        return s
    }()

    // MARK: Assets

    final class Assets {
        let work: URL
        var stills: [String: NSImage] = [:]
        var logo = Brand.appLogo
        init(work: URL) {
            self.work = work
            let snap = work.appendingPathComponent("snap")
            for seg in Hype.segs { if case .still(let n) = seg.src, stills[n] == nil { stills[n] = Trailer.load(snap, n, maxSide: 1800) } }
        }
        private var counts: [String: Int] = [:]
        func frame(_ dir: String, _ t: Double) -> NSImage? {
            let d = work.appendingPathComponent(dir)
            if counts[dir] == nil { counts[dir] = (try? FileManager.default.contentsOfDirectory(atPath: d.path))?.count ?? 1 }
            let i = Swift.max(1, Swift.min(counts[dir] ?? 1, Int(t * 60) + 1))
            return NSImage(contentsOf: d.appendingPathComponent(String(format: "f%05d.jpg", i)))
        }
    }

    @MainActor static func render(outDir: URL, work: URL) throws {
        let a = Assets(work: work)
        try IntroExporter.renderVideo(to: outDir.appendingPathComponent("hype-video.mp4"), size: size, fps: 60, duration: duration,
                                      frame: { t, sz in
            let r = ImageRenderer(content: HypeView(t: t, a: a).frame(width: sz.width, height: sz.height))
            r.scale = 1
            r.proposedSize = ProposedViewSize(sz)
            return r.cgImage
        }, progress: { p in print(String(format: "video %.0f%%", p * 100)); fflush(stdout) })
    }

    /// Time since the last beat (every `every` beats).
    static func sinceBeat(_ t: Double, every: Double = 1) -> Double {
        guard t >= first else { return 99 }
        return (t - first).truncatingRemainder(dividingBy: beat * every)
    }
}

// MARK: - Root

struct HypeView: View {
    let t: Double
    let a: Hype.Assets

    var body: some View {
        let H = Hype.self
        let k = (t - H.first) / H.beat - H.shift
        ZStack {
            Color.black
            if t >= H.B(8) && t < H.breakStart, let seg = H.segs.first(where: { k >= $0.from && k < $0.to }) {
                Shot(seg: seg, t: t, a: a, every: k < 28 ? 2 : 1, glitch: false)
            } else if t >= H.available && t < H.endCard {
                AvailableCard(t: t, a: a)
            } else if t >= H.B(62) && t < H.available, let seg = H.segs.first(where: { k >= $0.from && k < $0.to }) {
                Shot(seg: seg, t: t, a: a, every: 1, glitch: k < 64 || k >= 102)
            } else if t < H.Braw(4) {
                IntroCard(t: t, a: a)
            } else if t < H.B(8) {
                MacBookScene(u: t - H.Braw(4), a: a)
            } else if t >= H.breakStart && t < H.drop {
                BreakCard(t: t)
            } else if t >= H.drop && t < H.B(62) {
                DropCard(t: t, a: a)
            } else if t >= H.endCard {
                HypeEnd(t: t, a: a)
            }
            let sinceCut = cutAge(k)
            if sinceCut < 0.2 {
                Color.white.opacity((t >= H.drop && t < H.drop + 0.3 || (t >= H.available && t < H.available + 0.3) ? 0.9 : 0.3) * exp(-sinceCut * 22))
            }
            if t > H.duration - 0.05 { Color.black }
        }
        .frame(width: H.size.width, height: H.size.height)
        .clipped()
        .environment(\.colorScheme, .dark)
    }

    private func cutAge(_ k: Double) -> Double {
        let H = Hype.self
        var cuts = H.segs.map(\.from)
        cuts += [-12, -6, -3, -1, 1, 3, 50.7, 51, 52, 53, 54, 55, 58, 108, 110]
        guard let c = cuts.filter({ $0 <= k }).max() else { return 99 }
        return (k - c) * H.beat
    }
}

// MARK: - A shot: always shown whole (never cropped), caption underneath

private struct Shot: View {
    let seg: Hype.Seg
    let t: Double
    let a: Hype.Assets
    let every: Double
    let glitch: Bool

    // Room for the footage; the caption gets the band below it.
    static let box = CGSize(width: 1800, height: 820)

    var body: some View {
        let H = Hype.self
        let u = t - H.B(seg.from)
        let img: NSImage? = {
            switch seg.src {
            case .live(let dir, let t0): return a.frame(dir, t0 + u)
            case .still(let n): return a.stills[n]
            case .none: return nil
            }
        }()
        let punch = 1 + 0.025 * exp(-H.sinceBeat(t, every: every) * 13)
        let cutIn = 1 + 0.05 * exp(-u * 11)
        let scale = CGFloat(punch * cutIn)
        let shakeAmt = glitch ? 8 * exp(-H.sinceBeat(t) * 10) : 0
        let fit: CGSize = {
            guard let img, img.size.width > 0 else { return Self.box }
            let k = min(Self.box.width / img.size.width, Self.box.height / img.size.height)
            return CGSize(width: img.size.width * k, height: img.size.height * k)
        }()
        ZStack {
            if let img {
                // Soft blurred copy fills the edges (no black bars, nothing cut off).
                Image(nsImage: img).resizable().scaledToFill()
                    .frame(width: H.size.width, height: H.size.height).clipped()
                    .scaleEffect(1.15).blur(radius: 45).overlay(Color.black.opacity(0.55))
                ZStack {
                    Image(nsImage: img).resizable().interpolation(.high)
                        .frame(width: fit.width, height: fit.height)
                    if glitch && u < 0.35 {
                        let amt = CGFloat(12 * exp(-u * 9))
                        Image(nsImage: img).resizable().frame(width: fit.width, height: fit.height)
                            .colorMultiply(.red).offset(x: amt).blendMode(.plusLighter).opacity(0.4)
                        Image(nsImage: img).resizable().frame(width: fit.width, height: fit.height)
                            .colorMultiply(.cyan).offset(x: -amt).blendMode(.plusLighter).opacity(0.4)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.18), lineWidth: 2))
                .shadow(color: H.aqua.opacity(0.35), radius: 40)
                .scaleEffect(scale)
                .offset(y: -70)
            }
            SlamText(text: seg.text, age: u, size: 120)
                .offset(y: 455)
            BrandBug()
        }
        .offset(x: shakeAmt * sin(t * 97), y: shakeAmt * cos(t * 83))
        .frame(width: H.size.width, height: H.size.height)
        .clipped()
    }
}

/// Big compressed caps that slam in.
private struct SlamText: View {
    let text: String
    let age: Double
    var size: CGFloat = 120
    var color: Color = .white

    var body: some View {
        let p = min(1, age / 0.12)
        Text(text)
            .font(.system(size: size, weight: .black).width(.compressed))
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .frame(width: 1760)
            .shadow(color: .black.opacity(0.8), radius: 16, y: 5)
            .shadow(color: Hype.aqua.opacity(0.35), radius: 26)
            .scaleEffect(1.5 - 0.5 * p)
            .opacity(p)
            .blur(radius: 8 * (1 - p))
    }
}

private struct BrandBug: View {
    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(Hype.aqua).frame(width: 12, height: 12)
            Text("ARIES 2.0").font(.system(size: 26, weight: .black).width(.compressed)).tracking(3)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16).frame(height: 44)
        .background(Capsule().fill(.black.opacity(0.5)))
        .offset(x: -830, y: -495)
    }
}

// MARK: - MacBook intro

/// A MacBook flies in, opens, powers on and cycles through real footage, then the camera dives into the screen.
private struct MacBookScene: View {
    let u: Double
    let a: Hype.Assets

    var body: some View {
        let H = Hype.self
        let lb = u / H.beat                                     // beats into the scene (0…20)
        let fly = min(1.0, max(0, lb / 3))
        let flyE = 1 - pow(1 - fly, 3)
        let open = min(1.0, max(0, (lb - 3) / 3))
        let openE = open < 1 ? 1 - pow(1 - open, 3) * cos(open * 4) : 1
        let lidAngle = -88 + 82 * openE                         // flat → standing
        let power = min(1.0, max(0, (lb - 5.6) / 0.6))
        let dive = min(1.0, max(0, (lb - 17) / 3))
        let punch = 1 + 0.03 * exp(-H.sinceBeat(u + H.Braw(4), every: 2) * 12)
        ZStack {
            RadialGradient(colors: [H.aqua.opacity(0.25 + 0.35 * power), .clear], center: UnitPoint(x: 0.5, y: 0.45),
                           startRadius: 0, endRadius: 1000)
            VStack(spacing: 0) {
                Lid(lb: lb, power: power, a: a, u: u)
                    .rotation3DEffect(.degrees(lidAngle), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.35)
                // Base
                ZStack(alignment: .top) {
                    UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 30, bottomTrailingRadius: 30, topTrailingRadius: 6)
                        .fill(LinearGradient(colors: [Color(white: 0.78), Color(white: 0.42)], startPoint: .top, endPoint: .bottom))
                        .frame(width: 1220, height: 34)
                    Capsule().fill(Color(white: 0.3)).frame(width: 190, height: 9).offset(y: 2)
                }
            }
            .shadow(color: H.aqua.opacity(0.45 * power), radius: 60)
            .rotation3DEffect(.degrees(14 * (1 - flyE) + 4 * sin(u * 0.9)), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
            .scaleEffect(CGFloat((0.55 + 0.45 * flyE) * punch))
            .offset(y: 420 * (1 - flyE) - 60)
            .opacity(min(1, fly * 3))
            // Camera dives into the screen
            .scaleEffect(1 + 2.6 * dive * dive, anchor: UnitPoint(x: 0.5, y: 0.42))

            if lb >= 8 && lb < 13 {
                SlamCaption(text: "THE DYNAMIC ISLAND", age: u - 8 * H.beat, color: .white)
            } else if lb >= 13 && lb < 17.5 {
                SlamCaption(text: "FOR YOUR MAC.", age: u - 13 * H.beat, color: H.aqua)
            }
        }
    }
}

private struct Lid: View {
    let lb: Double
    let power: Double
    let a: Hype.Assets
    let u: Double

    var body: some View {
        let screen = CGSize(width: 1040, height: 650)
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 34, style: .continuous).fill(Color(white: 0.09))
                .overlay(RoundedRectangle(cornerRadius: 34, style: .continuous).stroke(Color(white: 0.32), lineWidth: 3))
            ZStack(alignment: .top) {
                LinearGradient(colors: [Color(red: 0.06, green: 0.08, blue: 0.16), Color(red: 0.12, green: 0.06, blue: 0.2)],
                               startPoint: .top, endPoint: .bottom)
                content
                Color.white.opacity(power > 0 && power < 1 ? 0.8 * (1 - power) : 0)
            }
            .frame(width: screen.width, height: screen.height)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .opacity(power)
            .padding(.top, 18)
            // The notch
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 12, bottomTrailingRadius: 12, topTrailingRadius: 0)
                .fill(.black).frame(width: 150, height: 26).padding(.top, 18)
        }
        .frame(width: screen.width + 36, height: screen.height + 36)
    }

    @ViewBuilder private var content: some View {
        let H = Hype.self
        let (dir, t0, top): (String, Double, Bool) = {
            switch lb {
            case ..<9: return ("ff6", 0.4, false)
            case ..<11: return ("fn4", 1.6, true)
            case ..<13: return ("set6", 1.3, false)
            case ..<15: return ("wn6", 0.6, false)
            default: return ("ff6", 6.4, false)
            }
        }()
        let start: Double = lb < 9 ? 5.6 : (lb < 11 ? 9 : (lb < 13 ? 11 : (lb < 15 ? 13 : 15)))
        if let img = a.frame(dir, t0 + max(0, u - start * H.beat)) {
            Image(nsImage: img).resizable().interpolation(.high).scaledToFit()
                .frame(width: 1040, height: 650, alignment: top ? .top : .center)
        }
    }
}

private struct SlamCaption: View {
    let text: String
    let age: Double
    let color: Color
    var body: some View {
        let p = min(1, max(0, age) / 0.12)
        Text(text)
            .font(.system(size: 120, weight: .black).width(.compressed))
            .foregroundStyle(color)
            .shadow(color: .black.opacity(0.8), radius: 16, y: 5)
            .shadow(color: Hype.aqua.opacity(0.35), radius: 26)
            .scaleEffect(1.5 - 0.5 * p)
            .opacity(p)
            .offset(y: 455)
    }
}

// MARK: - Cards

private struct LogoMark: View {
    let a: Hype.Assets
    var size: CGFloat
    var body: some View {
        if let logo = a.logo {
            Image(nsImage: logo).resizable().interpolation(.high).scaledToFit()
                .frame(width: size, height: size)
                .mask(RadialGradient(colors: [.black, .black, .clear], center: .center, startRadius: 0, endRadius: size * 0.48))
                .blendMode(.screen)
        }
    }
}

private struct IntroCard: View {
    let t: Double
    let a: Hype.Assets
    var body: some View {
        let H = Hype.self
        let k = (t - H.first) / H.beat
        let punch = 1 + 0.06 * exp(-H.sinceBeat(t) * 12)
        ZStack {
            RadialGradient(colors: [H.aqua.opacity(0.35 * punch), .clear], center: .center, startRadius: 0, endRadius: 900)
            if k < 4 {
                LogoMark(a: a, size: 600)
                    .scaleEffect(CGFloat((0.75 + 0.25 * min(1, max(0, k) / 0.4)) * punch))
                    .opacity(t < H.first ? 0 : 1)
                    .shadow(color: H.aqua.opacity(0.8), radius: 40)
            } else if k < 6 {
                SlamText(text: "THE DYNAMIC ISLAND", age: t - H.B(4), size: 210).scaleEffect(CGFloat(punch))
            } else {
                SlamText(text: "FOR YOUR MAC.", age: t - H.B(6), size: 240, color: H.aqua).scaleEffect(CGFloat(punch))
            }
        }
    }
}

private struct BreakCard: View {
    let t: Double
    var body: some View {
        let H = Hype.self
        let k = (t - H.first) / H.beat
        let build = max(0, (t - H.B(56)) / (H.drop - H.B(56)))
        func word(_ w: String, _ i: Int, _ size: CGFloat, _ c: Color = .white) -> some View {
            let at = H.B(51 + Double(i))
            return Text(w)
                .font(.system(size: size, weight: .black).width(.compressed))
                .foregroundStyle(c)
                .shadow(color: H.aqua.opacity(0.4), radius: 24)
                .scaleEffect(t >= at ? 1.5 - 0.5 * min(1, (t - at) / 0.12) : 1)
                .opacity(t >= at ? min(1, (t - at) / 0.12) : 0)
        }
        return VStack(spacing: -20) {
            HStack(spacing: 40) { word("EVERYTHING", 0, 190); word("YOUR", 1, 190) }
            word("NOTCH", 2, 320, H.aqua)
            HStack(spacing: 40) { word("CAN", 3, 190); word("BE.", 4, 190) }
        }
        .scaleEffect(1 + 0.12 * build * build)
        .offset(x: 8 * build * sin(t * 120), y: 8 * build * cos(t * 110))
        .opacity(k < 50.7 ? 0 : 1)
    }
}

private struct DropCard: View {
    let t: Double
    let a: Hype.Assets
    var body: some View {
        let H = Hype.self
        let u = t - H.drop
        let punch = 1 + 0.08 * exp(-H.sinceBeat(t) * 12)
        let shake = 18 * exp(-u * 5)
        ZStack {
            RadialGradient(colors: [H.aqua.opacity(0.6), Color(red: 0.2, green: 0.1, blue: 0.6).opacity(0.3), .clear],
                           center: .center, startRadius: 0, endRadius: 1100)
            ForEach(0..<3, id: \.self) { r in
                let rp = min(1, max(0, (u - Double(r) * 0.1) / 0.8))
                Circle().stroke(H.aqua.opacity(0.7 * (1 - rp)), lineWidth: 8)
                    .frame(width: 200 + 2200 * rp, height: 200 + 2200 * rp)
            }
            HStack(spacing: 40) {
                LogoMark(a: a, size: 420).shadow(color: H.aqua, radius: 40)
                VStack(spacing: -30) {
                    Text("2.0")
                        .font(.system(size: 420, weight: .black).width(.compressed))
                        .foregroundStyle(LinearGradient(colors: [.white, H.aqua], startPoint: .top, endPoint: .bottom))
                        .shadow(color: H.aqua.opacity(0.9), radius: 60)
                    Text("AQUATIC").font(.system(size: 90, weight: .black).width(.compressed)).tracking(18)
                        .foregroundStyle(.white)
                }
            }
            .scaleEffect(CGFloat((1.7 - 0.7 * min(1, u / 0.15)) * punch))
        }
        .offset(x: shake * sin(t * 97), y: shake * cos(t * 89))
    }
}

/// "AVAILABLE NOW." — the big call-to-action slam right before the end card.
private struct AvailableCard: View {
    let t: Double
    let a: Hype.Assets
    var body: some View {
        let H = Hype.self
        let u = t - H.available
        let p = min(1, u / 0.14)
        let p2 = min(1, max(0, (u - H.beat) / 0.14))
        let shake = 14 * exp(-u * 6)
        ZStack {
            RadialGradient(colors: [H.aqua.opacity(0.65), Color(red: 0.25, green: 0.12, blue: 0.7).opacity(0.35), .clear],
                           center: .center, startRadius: 0, endRadius: 1150)
            ForEach(0..<4, id: \.self) { r in
                let rp = min(1, max(0, (u - Double(r) * 0.08) / 0.7))
                Circle().stroke(H.aqua.opacity(0.75 * (1 - rp)), lineWidth: 10)
                    .frame(width: 160 + 2300 * rp, height: 160 + 2300 * rp)
            }
            VStack(spacing: -40) {
                Text("AVAILABLE")
                    .font(.system(size: 300, weight: .black).width(.compressed))
                    .foregroundStyle(.white)
                    .shadow(color: H.aqua.opacity(0.9), radius: 50)
                    .scaleEffect(CGFloat(1.6 - 0.6 * p)).opacity(p).blur(radius: 10 * (1 - p))
                Text("NOW.")
                    .font(.system(size: 300, weight: .black).width(.compressed))
                    .foregroundStyle(LinearGradient(colors: [.white, H.aqua], startPoint: .top, endPoint: .bottom))
                    .shadow(color: H.aqua.opacity(0.9), radius: 50)
                    .scaleEffect(CGFloat(1.6 - 0.6 * p2)).opacity(p2).blur(radius: 10 * (1 - p2))
            }
            Text("FREE  ·  macOS")
                .font(.system(size: 46, weight: .black).width(.compressed)).tracking(14)
                .foregroundStyle(.white.opacity(0.85))
                .offset(y: 420).opacity(p2)
        }
        .offset(x: shake * sin(t * 97), y: shake * cos(t * 89))
    }
}

/// A bright diagonal light sweep, `u` seconds after it starts.
private struct Shine: View {
    let u: Double
    var body: some View {
        let x = -1400 + 2800 * min(1, max(0, u / 0.55))
        LinearGradient(colors: [.clear, .white.opacity(0.95), .clear], startPoint: .leading, endPoint: .trailing)
            .frame(width: 260, height: 1600)
            .rotationEffect(.degrees(20))
            .offset(x: x)
            .opacity(u > 0 && u < 0.6 ? 1 : 0)
            .blendMode(.plusLighter)
    }
}

private struct HypeEnd: View {
    let t: Double
    let a: Hype.Assets
    static let url = "github.com/maxxforgestudio-del/aries-dynamic-island"
    static let qr: NSImage? = {
        guard let f = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        f.setValue(Data(("https://" + url).utf8), forKey: "inputMessage")
        f.setValue("M", forKey: "inputCorrectionLevel")
        guard let img = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)) else { return nil }
        let rep = NSCIImageRep(ciImage: img)
        let ns = NSImage(size: rep.size)
        ns.addRepresentation(rep)
        return ns
    }()

    private func appear(_ u: Double, _ at: Double) -> Double { min(1, max(0, (u - at) / 0.15)) }

    var body: some View {
        let H = Hype.self
        let u = t - H.endCard
        let punch = 1 + 0.04 * exp(-H.sinceBeat(t, every: 2) * 10)
        ZStack {
            RadialGradient(colors: [H.aqua.opacity(0.4), .clear], center: .center, startRadius: 0, endRadius: 1000)
            HStack(spacing: 44) {
                LogoMark(a: a, size: 300).shadow(color: H.aqua.opacity(0.8), radius: 40)
                    .scaleEffect(CGFloat(punch))
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        Circle().fill(Color.green).frame(width: 16, height: 16)
                            .shadow(color: .green, radius: 8 + 6 * CGFloat(punch - 1) * 25)
                        Text("AVAILABLE NOW").font(.system(size: 30, weight: .black).width(.compressed)).tracking(6)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22).frame(height: 54)
                    .background(Capsule().fill(.white.opacity(0.12)))
                    .overlay(Capsule().stroke(.white.opacity(0.35), lineWidth: 2))
                    .opacity(appear(u, 0.0))
                    Text("ARIES DYNAMIC ISLAND")
                        .font(.system(size: 104, weight: .black).width(.compressed)).foregroundStyle(.white).fixedSize()
                        .opacity(appear(u, 0.05))
                    Text("2.0 AQUATIC · FREE DOWNLOAD FOR MAC")
                        .font(.system(size: 64, weight: .black).width(.compressed)).foregroundStyle(H.aqua).fixedSize()
                        .opacity(appear(u, 0.35))
                    // Where to get it
                    HStack(spacing: 14) {
                        Image(systemName: "arrow.down.circle.fill").font(.system(size: 40, weight: .bold))
                        Text(Self.url).font(.system(size: 31, weight: .bold, design: .monospaced)).fixedSize()
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 28).frame(height: 84)
                    .background(Capsule().fill(.white))
                    .shadow(color: H.aqua.opacity(0.8), radius: 30)
                    .scaleEffect(CGFloat(0.7 + 0.3 * appear(u, 0.7)), anchor: .leading)
                    .opacity(appear(u, 0.7))
                    .padding(.top, 8)
                    Text("Or search “Aries Dynamic Island” on GitHub  ·  Download the .zip from Releases")
                        .font(.system(size: 24, weight: .semibold)).foregroundStyle(.white.opacity(0.75)).fixedSize()
                        .opacity(appear(u, 1.1))
                    Text("A MAXX FORGE STUDIO PRODUCT  ·  MUSIC: LOVEBOY1939 – USER_ERROR_REMIX")
                        .font(.system(size: 18, weight: .semibold)).tracking(3).foregroundStyle(.white.opacity(0.45)).fixedSize()
                        .opacity(appear(u, 1.5))
                        .padding(.top, 6)
                }
                if let qr = Self.qr {
                    VStack(spacing: 12) {
                        Image(nsImage: qr).interpolation(.none).resizable()
                            .frame(width: 230, height: 230)
                            .padding(16)
                            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.white))
                            .shadow(color: H.aqua.opacity(0.6), radius: 30)
                        Text("SCAN TO DOWNLOAD").font(.system(size: 24, weight: .black).width(.compressed)).tracking(3)
                            .foregroundStyle(.white)
                    }
                    .scaleEffect(CGFloat(0.6 + 0.4 * appear(u, 0.9)))
                    .opacity(appear(u, 0.9))
                }
            }
            // Gentle fade to black at the very end.
            Color.black.opacity(min(1, max(0, (t - (H.duration - 0.6)) / 0.6)))
        }
    }
}

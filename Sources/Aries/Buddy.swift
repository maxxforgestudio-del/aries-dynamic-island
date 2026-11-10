import SwiftUI
import AppKit

/// Aries, a little ram who lives in your notch. Blinks, follows your cursor,
/// bobs along to music and gets sleepy late at night.
struct BuddyView: View {
    enum Mood { case happy, vibing, sleepy, low }

    var mood: Mood
    var accent: Color
    var size: CGFloat = 64

    @ViewState private var poke = 0.0

    private let wool = Color(red: 0.98, green: 0.96, blue: 0.93)
    private let face = Color(red: 0.99, green: 0.88, blue: 0.80)
    private let horn = Color(red: 0.86, green: 0.68, blue: 0.52)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let bob = mood == .vibing ? sin(t * 2 * .pi * 1.8) * size * 0.05 : sin(t * 1.3) * size * 0.015
            let tilt = mood == .vibing ? sin(t * 2 * .pi * 0.9) * 6 : 0
            let blink = isBlinking(t) || mood == .sleepy
            let look = lookOffset()

            ZStack {
                // Horns (ram curls)
                hornView.offset(x: -size * 0.40, y: -size * 0.02)
                hornView.scaleEffect(x: -1, y: 1).offset(x: size * 0.40, y: -size * 0.02)

                // Head
                Ellipse()
                    .fill(LinearGradient(colors: [face, face.opacity(0.92)], startPoint: .top, endPoint: .bottom))
                    .frame(width: size * 0.72, height: size * 0.66)
                    .offset(y: size * 0.06)

                // Wool tuft
                ForEach(0..<5, id: \.self) { i in
                    Circle()
                        .fill(wool)
                        .frame(width: size * 0.24, height: size * 0.24)
                        .offset(x: size * (-0.2 + 0.1 * Double(i)),
                                y: -size * 0.24 + (i % 2 == 0 ? 0 : -size * 0.04))
                }

                // Eyes
                HStack(spacing: size * 0.17) {
                    eye(blink: blink, look: look)
                    eye(blink: blink, look: look)
                }
                .offset(y: size * 0.04)

                // Cheeks
                HStack(spacing: size * 0.36) {
                    Circle().fill(Color.pink.opacity(0.45)).frame(width: size * 0.1)
                    Circle().fill(Color.pink.opacity(0.45)).frame(width: size * 0.1)
                }
                .offset(y: size * 0.16)

                mouth.offset(y: size * 0.22)

                if mood == .sleepy {
                    Text("z")
                        .font(.system(size: size * 0.2, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))
                        .offset(x: size * 0.42, y: -size * 0.36 - CGFloat((t * 8).truncatingRemainder(dividingBy: 8)))
                        .opacity(1 - (t * 1).truncatingRemainder(dividingBy: 1))
                }
                if mood == .vibing {
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.2, weight: .bold))
                        .foregroundStyle(accent)
                        .offset(x: size * 0.46, y: -size * 0.3 + sin(t * 3) * 3)
                        .rotationEffect(.degrees(sin(t * 2) * 12))
                }
            }
            .frame(width: size * 1.2, height: size * 1.1)
            .rotationEffect(.degrees(tilt + poke * sin(t * 30) * 8))
            .offset(y: bob)
            .scaleEffect(1 + poke * 0.12)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // Boop!
            withAnimation(.spring(response: 0.2, dampingFraction: 0.4)) { poke = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { poke = 0 }
            }
        }
    }

    private var hornView: some View {
        ZStack {
            Circle().trim(from: 0.05, to: 0.9)
                .stroke(horn, style: StrokeStyle(lineWidth: size * 0.09, lineCap: .round))
                .frame(width: size * 0.26, height: size * 0.26)
            Circle().trim(from: 0.3, to: 0.95)
                .stroke(horn.opacity(0.85), style: StrokeStyle(lineWidth: size * 0.06, lineCap: .round))
                .frame(width: size * 0.11, height: size * 0.11)
        }
        .rotationEffect(.degrees(-30))
    }

    private func eye(blink: Bool, look: CGSize) -> some View {
        ZStack {
            Capsule()
                .fill(Color(white: 0.12))
                .frame(width: size * 0.11, height: blink ? size * 0.025 : size * 0.15)
            if !blink {
                Circle().fill(.white)
                    .frame(width: size * 0.045)
                    .offset(x: -size * 0.015 + look.width * 0.3, y: -size * 0.03 + look.height * 0.3)
            }
        }
        .offset(x: blink ? 0 : look.width, y: blink ? 0 : look.height)
    }

    private var mouth: some View {
        Path { p in
            let w = size * 0.12
            switch mood {
            case .low:
                p.move(to: CGPoint(x: -w / 2, y: w * 0.25))
                p.addQuadCurve(to: CGPoint(x: w / 2, y: w * 0.25), control: CGPoint(x: 0, y: -w * 0.2))
            case .sleepy:
                p.addEllipse(in: CGRect(x: -w * 0.18, y: -w * 0.1, width: w * 0.36, height: w * 0.36))
            default:
                p.move(to: CGPoint(x: -w / 2, y: 0))
                p.addQuadCurve(to: CGPoint(x: w / 2, y: 0), control: CGPoint(x: 0, y: w * (mood == .vibing ? 0.9 : 0.6)))
            }
        }
        .stroke(Color(white: 0.15), style: StrokeStyle(lineWidth: size * 0.03, lineCap: .round))
        .frame(width: 1, height: 1)
    }

    private func isBlinking(_ t: Double) -> Bool {
        let period = 3.7
        let phase = t.truncatingRemainder(dividingBy: period)
        let double = (t / period).truncatingRemainder(dividingBy: 3) < 1
        return phase < 0.12 || (double && phase > 0.22 && phase < 0.32)
    }

    /// Pupils glance toward the cursor.
    private func lookOffset() -> CGSize {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else { return .zero }
        let m = NSEvent.mouseLocation
        let origin = CGPoint(x: screen.frame.midX - 180, y: screen.frame.maxY - 90)
        let dx = max(-1, min(1, (m.x - origin.x) / 300))
        let dy = max(-1, min(1, (origin.y - m.y) / 200))
        return CGSize(width: dx * size * 0.035, height: dy * size * 0.03)
    }
}

/// Little confetti pop from the island (timer done, etc.).
struct ConfettiView: View {
    var trigger: Int
    var originY: CGFloat

    @ViewState private var engine = ConfettiEngine()
    @ViewState private var running = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !running)) { tl in
            Canvas { ctx, size in
                let now = tl.date.timeIntervalSinceReferenceDate
                engine.step(now: now)
                for p in engine.pieces {
                    let age = now - p.born
                    var c = ctx
                    c.opacity = max(0, 1 - age / p.life)
                    c.translateBy(x: size.width / 2 + p.x, y: originY + p.y)
                    c.rotate(by: .degrees(p.spin * age))
                    let r = CGRect(x: -p.size / 2, y: -p.size / 4, width: p.size, height: p.size * (p.round ? 1 : 0.5))
                    c.fill(p.round ? Path(ellipseIn: r) : Path(roundedRect: r, cornerRadius: 1.5), with: .color(p.color))
                }
            }
        }
        .onChange(of: trigger) { _, _ in
            engine.burst()
            running = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { running = false }
        }
        .allowsHitTesting(false)
    }
}

final class ConfettiEngine {
    struct Piece {
        var x = 0.0, y = 0.0, vx: Double, vy: Double
        var born: Double, life: Double
        var size: Double, spin: Double
        var color: Color, round: Bool
    }
    private(set) var pieces: [Piece] = []
    private var last = 0.0
    private var pending = false
    var isIdle: Bool { pieces.isEmpty && !pending }

    private let palette: [Color] = [.pink, .orange, .yellow, .mint, .cyan, .purple, Color(red: 1, green: 0.5, blue: 0.6)]

    func burst() { pending = true }

    func step(now: Double) {
        if pending {
            pending = false
            for _ in 0..<46 {
                let angle = Double.random(in: 0.15 * .pi...0.85 * .pi)
                let speed = Double.random(in: 120...300)
                pieces.append(Piece(vx: cos(angle) * speed * 1.4, vy: sin(angle) * speed * 0.6,
                                    born: now, life: .random(in: 1.2...2.0),
                                    size: .random(in: 5...9), spin: .random(in: -540...540),
                                    color: palette.randomElement()!, round: Bool.random()))
            }
        }
        let dt = last == 0 ? 0 : min(0.05, now - last)
        last = now
        for i in pieces.indices {
            pieces[i].x += pieces[i].vx * dt
            pieces[i].y += pieces[i].vy * dt
            pieces[i].vy += 380 * dt
            pieces[i].vx *= (1 - 1.2 * dt)
        }
        pieces.removeAll { now - $0.born > $0.life }
    }
}

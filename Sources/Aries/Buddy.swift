import SwiftUI
import AppKit

/// Aries, the little ram who lives in your notch (2.0 "Aquatic" design).
/// Blinks, follows your cursor, wears headphones while music plays, dozes at night,
/// worries when the battery is low, and sends hearts when you tap it.
struct BuddyView: View {
    enum Mood { case happy, vibing, sleepy, low }

    var mood: Mood
    var accent: Color
    var size: CGFloat = 64

    @ViewState private var boop = 0.0
    @ViewState private var hearts: [Double] = []

    private let woolLight = Color(red: 1.0, green: 0.98, blue: 1.0)
    private let woolShade = Color(red: 0.86, green: 0.84, blue: 0.97)
    private let skin = Color(red: 1.0, green: 0.87, blue: 0.80)
    private let skinShade = Color(red: 0.96, green: 0.74, blue: 0.68)
    private let hornA = Color(red: 1.0, green: 0.84, blue: 0.48)
    private let hornB = Color(red: 0.78, green: 0.55, blue: 0.30)
    private let ink = Color(red: 0.13, green: 0.12, blue: 0.22)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: A11y.reduceMotion)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let still = A11y.reduceMotion
            let bob = still ? 0 : (mood == .vibing ? sin(t * 2 * .pi * 1.8) * size * 0.05 : sin(t * 1.4) * size * 0.012)
            let tilt = still ? 0 : (mood == .vibing ? sin(t * 2 * .pi * 0.9) * 7 : sin(t * 0.7) * 1.5)
            let breathe = still ? 1 : 1 + sin(t * 2.1) * 0.012
            let blink = !still && isBlinking(t)
            let look = lookOffset()

            ZStack {
                // Soft shadow
                Ellipse().fill(.black.opacity(0.35)).frame(width: size * 0.62, height: size * 0.09)
                    .blur(radius: 3).offset(y: size * 0.47)

                ZStack {
                    horn.offset(x: -size * 0.39, y: size * 0.02).rotationEffect(.degrees(still ? 0 : sin(t * 1.1) * 3))
                    horn.scaleEffect(x: -1, y: 1).offset(x: size * 0.39, y: size * 0.02)
                        .rotationEffect(.degrees(still ? 0 : -sin(t * 1.1) * 3))

                    // Fluffy head of wool
                    ZStack {
                        ForEach(0..<9, id: \.self) { i in
                            let a = Double(i) / 9 * 2 * .pi
                            Circle()
                                .fill(RadialGradient(colors: [woolLight, woolShade], center: .topLeading,
                                                     startRadius: 0, endRadius: size * 0.22))
                                .frame(width: size * 0.3, height: size * 0.3)
                                .offset(x: cos(a) * size * 0.25, y: sin(a) * size * 0.22 - size * 0.04)
                        }
                        Circle().fill(woolLight).frame(width: size * 0.6, height: size * 0.56).offset(y: -size * 0.03)
                    }

                    // Face
                    Ellipse()
                        .fill(LinearGradient(colors: [skin, skinShade], startPoint: .top, endPoint: .bottom))
                        .frame(width: size * 0.56, height: size * 0.5)
                        .offset(y: size * 0.09)
                        .shadow(color: .black.opacity(0.08), radius: 1, y: 1)

                    // Fringe tuft
                    HStack(spacing: -size * 0.05) {
                        ForEach(0..<3, id: \.self) { _ in
                            Circle().fill(woolLight).frame(width: size * 0.17)
                        }
                    }
                    .offset(y: -size * 0.13)

                    eyes(blink: blink, look: look).offset(y: size * 0.07)

                    // Cheeks
                    HStack(spacing: size * 0.3) {
                        Circle().fill(Color.pink.opacity(0.5)).frame(width: size * 0.09)
                        Circle().fill(Color.pink.opacity(0.5)).frame(width: size * 0.09)
                    }
                    .blur(radius: 0.6)
                    .offset(y: size * 0.18)

                    mouth.offset(y: size * 0.23)

                    if mood == .vibing { headphones }
                    if mood == .low {
                        Image(systemName: "drop.fill")
                            .font(.system(size: size * 0.1))
                            .foregroundStyle(.cyan.opacity(0.85))
                            .offset(x: size * 0.25, y: -size * 0.02)
                    }
                }
                .scaleEffect(breathe)
                .rotationEffect(.degrees(tilt + boop * sin(t * 28) * 9))
                .offset(y: bob - boop * size * 0.06)

                if mood == .sleepy {
                    ForEach(0..<2, id: \.self) { i in
                        let phase = (t * 0.5 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
                        Text("z")
                            .font(.system(size: size * (0.14 + 0.06 * Double(i)), weight: .heavy, design: .rounded))
                            .foregroundStyle(.white.opacity(0.85 * (1 - phase)))
                            .offset(x: size * (0.36 + phase * 0.12), y: -size * (0.26 + phase * 0.28))
                    }
                }
                if mood == .vibing && !still {
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.17, weight: .bold))
                        .foregroundStyle(accent)
                        .offset(x: size * 0.5, y: -size * 0.32 + sin(t * 3) * 3)
                        .rotationEffect(.degrees(sin(t * 2) * 12))
                }
                ForEach(Array(hearts.enumerated()), id: \.offset) { i, born in
                    let age = t - born
                    if age < 1.2 {
                        Image(systemName: "heart.fill")
                            .font(.system(size: size * 0.14))
                            .foregroundStyle(.pink)
                            .opacity(1 - age / 1.2)
                            .offset(x: (Double(i % 3) - 1) * size * 0.25 + sin(age * 6 + Double(i)) * 3,
                                    y: -size * 0.3 - age * size * 0.5)
                            .scaleEffect(0.6 + age * 0.5)
                    }
                }
            }
            .frame(width: size * 1.25, height: size * 1.15)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            let now = Date().timeIntervalSinceReferenceDate
            hearts = [now, now + 0.08, now + 0.16]
            withAnimation(.spring(response: 0.2, dampingFraction: 0.35)) { boop = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) { boop = 0 }
            }
            if Prefs.bool(Prefs.haptics) { NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now) }
        }
        .accessibilityLabel("Aries the ram, \(moodLabel)")
    }

    private var moodLabel: String {
        switch mood { case .happy: "happy"; case .vibing: "listening to music"; case .sleepy: "sleepy"; case .low: "worried about the battery" }
    }

    private var horn: some View {
        RamHorn()
            .stroke(LinearGradient(colors: [hornA, hornB], startPoint: .top, endPoint: .bottom),
                    style: StrokeStyle(lineWidth: size * 0.085, lineCap: .round, lineJoin: .round))
            .frame(width: size * 0.3, height: size * 0.3)
            .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
    }

    private func eyes(blink: Bool, look: CGSize) -> some View {
        let closedHappy = mood == .vibing
        let lidded = mood == .sleepy
        return HStack(spacing: size * 0.14) {
            ForEach(0..<2, id: \.self) { _ in
                ZStack {
                    if closedHappy || lidded || blink {
                        // ^ ^ happy arcs or sleepy lids
                        ArcShape(up: closedHappy)
                            .stroke(ink, style: StrokeStyle(lineWidth: size * 0.032, lineCap: .round))
                            .frame(width: size * 0.12, height: size * 0.06)
                    } else {
                        Ellipse().fill(ink).frame(width: size * 0.13, height: size * 0.16)
                        Circle().fill(.white).frame(width: size * 0.055)
                            .offset(x: -size * 0.022 + look.width * 0.4, y: -size * 0.035 + look.height * 0.4)
                        Circle().fill(.white.opacity(0.8)).frame(width: size * 0.022)
                            .offset(x: size * 0.03 + look.width * 0.4, y: size * 0.035 + look.height * 0.4)
                    }
                }
                .frame(width: size * 0.14, height: size * 0.17)
                .offset(x: (closedHappy || lidded || blink) ? 0 : look.width, y: (closedHappy || lidded || blink) ? 0 : look.height)
                .overlay(alignment: .top) {
                    if mood == .low {
                        Capsule().fill(ink).frame(width: size * 0.1, height: size * 0.022)
                            .rotationEffect(.degrees(-12)).offset(y: -size * 0.05)
                    }
                }
            }
        }
    }

    private var mouth: some View {
        Group {
            switch mood {
            case .low:
                ArcShape(up: true)
                    .stroke(ink, style: StrokeStyle(lineWidth: size * 0.028, lineCap: .round))
                    .frame(width: size * 0.1, height: size * 0.035)
            case .sleepy:
                Ellipse().fill(ink.opacity(0.85)).frame(width: size * 0.05, height: size * 0.06)
            case .vibing:
                ZStack {
                    HalfCircle().fill(ink).frame(width: size * 0.13, height: size * 0.08)
                    HalfCircle().fill(Color.pink).frame(width: size * 0.07, height: size * 0.035).offset(y: size * 0.018)
                }
            case .happy:
                ArcShape(up: false)
                    .stroke(ink, style: StrokeStyle(lineWidth: size * 0.028, lineCap: .round))
                    .frame(width: size * 0.12, height: size * 0.045)
            }
        }
    }

    private var headphones: some View {
        ZStack {
            Circle()
                .trim(from: 0.55, to: 0.95)
                .stroke(accent.gradient, style: StrokeStyle(lineWidth: size * 0.06, lineCap: .round))
                .frame(width: size * 0.8, height: size * 0.8)
                .offset(y: size * 0.08)
            HStack(spacing: size * 0.6) {
                RoundedRectangle(cornerRadius: size * 0.06).fill(accent.gradient)
                    .frame(width: size * 0.13, height: size * 0.2)
                RoundedRectangle(cornerRadius: size * 0.06).fill(accent.gradient)
                    .frame(width: size * 0.13, height: size * 0.2)
            }
            .offset(y: size * 0.12)
        }
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
        return CGSize(width: dx * size * 0.03, height: dy * size * 0.025)
    }
}

/// A curled ram horn (spiral).
struct RamHorn: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: r.midX, y: r.midY)
        let maxR = min(r.width, r.height) / 2
        let steps = 90
        for i in 0...steps {
            let f = Double(i) / Double(steps)
            let ang = -.pi / 2 - f * 1.75 * 2 * .pi
            let rad = maxR * (1 - f * 0.78)
            let pt = CGPoint(x: c.x + cos(ang) * rad, y: c.y + sin(ang) * rad)
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        return p
    }
}

struct ArcShape: Shape {
    var up: Bool
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: up ? r.maxY : r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: up ? r.maxY : r.minY),
                       control: CGPoint(x: r.midX, y: up ? r.minY - r.height : r.maxY + r.height))
        return p
    }
}

struct HalfCircle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.minY), control: CGPoint(x: r.midX, y: r.maxY + r.height * 0.6))
        return p
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

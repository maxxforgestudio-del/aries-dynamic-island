import SwiftUI

/// Subtle music notes that drift out from the island's wings while music plays.
struct MusicNotesView: View {
    var islandWidth: CGFloat
    var islandHeight: CGFloat
    var color: Color
    var intensity: Double
    var active: Bool

    @ViewState private var engine = NoteEngine()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !active && engine.isEmpty)) { tl in
            Canvas { ctx, size in
                let now = tl.date.timeIntervalSinceReferenceDate
                engine.step(now: now, size: size, islandWidth: islandWidth, islandHeight: islandHeight,
                            intensity: intensity, spawning: active)
                let symbols = ["music.note", "music.quarternote.3", "music.note", "music.note.list"]
                let resolved: [GraphicsContext.ResolvedImage] = symbols.map {
                    var img = ctx.resolve(Image(systemName: $0))
                    img.shading = .color(color)
                    return img
                }
                let peak = 0.22 + 0.5 * intensity
                for p in engine.particles {
                    let f = (now - p.born) / p.life
                    guard f >= 0, f <= 1 else { continue }
                    var c = ctx
                    let alpha = sin(.pi * min(1, f * 1.4)) * (1 - f) * peak * 1.6
                    c.opacity = max(0, min(1, alpha))
                    let sway = sin((now - p.born) * 2.6 + p.phase) * 3.5
                    c.translateBy(x: p.x + sway, y: p.y)
                    c.rotate(by: .degrees(p.rotation + p.spin * (now - p.born)))
                    let s = p.size * (0.75 + 0.35 * min(1, f * 3))
                    c.draw(resolved[p.symbol], in: CGRect(x: -s / 2, y: -s / 2, width: s, height: s))
                }
            }
        }
    }
}

final class NoteEngine {
    struct Particle {
        var x: Double, y: Double
        var vx: Double, vy: Double
        var born: Double, life: Double
        var size: Double
        var rotation: Double, spin: Double
        var phase: Double
        var symbol: Int
    }

    private(set) var particles: [Particle] = []
    private var lastStep: Double = 0
    private var nextSpawn: Double = 0
    private var side: Double = 1

    var isEmpty: Bool { particles.isEmpty }

    func step(now: Double, size: CGSize, islandWidth: CGFloat, islandHeight: CGFloat,
              intensity: Double, spawning: Bool) {
        let dt = lastStep == 0 ? 0 : min(0.1, now - lastStep)
        lastStep = now

        if spawning, now >= nextSpawn {
            side = -side
            let cx = Double(size.width) / 2
            let edge = Double(islandWidth) / 2 - 16
            particles.append(Particle(
                x: cx + side * (edge + .random(in: -6...4)),
                y: Double(islandHeight) - 8,
                vx: side * .random(in: 9...20),
                vy: .random(in: 9...17),
                born: now, life: .random(in: 2.0...2.8),
                size: .random(in: 9...13),
                rotation: side * .random(in: -10...18), spin: side * .random(in: 4...16),
                phase: .random(in: 0...6.28),
                symbol: Int.random(in: 0..<4)))
            let interval = 1.7 - 1.25 * min(1, max(0, intensity))
            nextSpawn = now + interval * .random(in: 0.75...1.3)
        }

        for i in particles.indices {
            particles[i].x += particles[i].vx * dt
            particles[i].y += particles[i].vy * dt
            particles[i].vx *= (1 - 0.35 * dt)
        }
        particles.removeAll { now - $0.born > $0.life }
    }
}

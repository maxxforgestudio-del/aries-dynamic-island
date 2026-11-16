import AppKit
import SwiftUI

/// A Live Activity that any app, script or Shortcut can start through an `aries://` link.
///
///   aries://activity?id=pizza&title=Pizza&subtitle=Out%20for%20delivery&icon=bicycle&color=orange&progress=0.6
///   aries://activity/end?id=pizza
///   aries://toast?title=Build%20finished&icon=checkmark.seal.fill&color=green
///   aries://timer?minutes=25        aries://focus        aries://stopwatch
///   aries://note?text=Buy%20milk     aries://open?tab=music
struct LiveActivity: Identifiable, Equatable, Hashable {
    let id: String
    var title: String
    var subtitle: String
    var icon: String
    var color: Color
    var progress: Double?
    var updated = Date()
}

final class LiveActivityCenter: ObservableObject {
    @Published private(set) var activities: [LiveActivity] = []
    var current: LiveActivity? { activities.last }

    func upsert(_ a: LiveActivity) {
        if let i = activities.firstIndex(where: { $0.id == a.id }) { activities[i] = a } else { activities.append(a) }
    }
    func end(_ id: String) { activities.removeAll { $0.id == id } }
    func endAll() { activities.removeAll() }

    static func color(_ name: String?) -> Color {
        switch name?.lowercased() {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "mint": return .mint
        case "teal", "cyan": return .cyan
        case "blue": return .blue
        case "indigo": return .indigo
        case "purple": return .purple
        case "pink": return .pink
        case let hex? where hex.count == 6 || (hex.hasPrefix("#") && hex.count == 7):
            let v = UInt64(hex.replacingOccurrences(of: "#", with: ""), radix: 16) ?? 0xFFFFFF
            return Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
        default: return .white
        }
    }
}

/// Focus sessions (Pomodoro) and a stopwatch, built on top of the timer.
final class FocusModel: ObservableObject {
    enum Phase: Equatable { case off, focus, rest }
    @Published private(set) var phase: Phase = .off
    @Published private(set) var round = 0
    @Published private(set) var stopwatchStart: Date?
    @Published private(set) var stopwatchAccum: Double = 0

    var focusMinutes = 25.0, breakMinutes = 5.0

    func startFocus(_ timer: TimerModel) {
        round = 1
        phase = .focus
        timer.start(minutes: focusMinutes)
    }

    func stopFocus(_ timer: TimerModel) {
        phase = .off
        timer.stop()
    }

    /// Called when the timer ends; returns a message to show.
    func timerEnded(_ timer: TimerModel) -> (String, String)? {
        switch phase {
        case .focus:
            phase = .rest
            timer.start(minutes: breakMinutes)
            return ("cup.and.saucer.fill", "Break time")
        case .rest:
            round += 1
            phase = .focus
            timer.start(minutes: focusMinutes)
            return ("brain.head.profile", "Focus round \(round)")
        case .off:
            return nil
        }
    }

    var stopwatchRunning: Bool { stopwatchStart != nil }
    var stopwatchActive: Bool { stopwatchStart != nil || stopwatchAccum > 0 }
    func stopwatchElapsed(at d: Date = Date()) -> Double {
        stopwatchAccum + (stopwatchStart.map { d.timeIntervalSince($0) } ?? 0)
    }
    func toggleStopwatch() {
        if let s = stopwatchStart { stopwatchAccum += Date().timeIntervalSince(s); stopwatchStart = nil }
        else { stopwatchStart = Date() }
    }
    func resetStopwatch() { stopwatchStart = nil; stopwatchAccum = 0 }

    static func format(_ s: Double) -> String {
        let cs = Int((s * 100).rounded(.down))
        let m = cs / 6000, sec = (cs / 100) % 60, c = cs % 100
        return m >= 60 ? String(format: "%d:%02d:%02d", m / 60, m % 60, sec) : String(format: "%d:%02d.%02d", m, sec, c)
    }
}

// MARK: - Views

/// The second activity, split off into its own little bubble beside the island (like iPhone).
struct SecondaryBubble: View {
    @ObservedObject var model: IslandModel
    let kind: IslandModel.Secondary
    let diameter: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            ZStack {
                Circle().fill(.black)
                switch kind {
                case .timer:
                    ring(1 - model.timer.progress(at: ctx.date), .orange)
                    Image(systemName: model.focus.phase == .rest ? "cup.and.saucer.fill" :
                            (model.focus.phase == .focus ? "brain.head.profile" : "timer"))
                        .font(.system(size: diameter * 0.32, weight: .bold)).foregroundStyle(.orange)
                case .download:
                    if let p = model.downloads.current?.progress { ring(p, .green) } else { ring(0.3, .green) }
                    Image(systemName: "arrow.down").font(.system(size: diameter * 0.32, weight: .black)).foregroundStyle(.green)
                case .activity:
                    let a = model.live.current
                    if let p = a?.progress { ring(p, a?.color ?? .white) }
                    Image(systemName: a?.icon ?? "sparkles").font(.system(size: diameter * 0.36, weight: .bold))
                        .foregroundStyle(a?.color ?? .white)
                case .privacy:
                    Image(systemName: model.system.cameraActive ? "video.fill" : "mic.fill")
                        .font(.system(size: diameter * 0.36, weight: .bold))
                        .foregroundStyle(model.system.cameraActive ? .green : .orange)
                case .stopwatch:
                    Image(systemName: "stopwatch.fill").font(.system(size: diameter * 0.4, weight: .bold)).foregroundStyle(.yellow)
                }
            }
            .frame(width: diameter, height: diameter)
        }
        .contentShape(Circle())
        .onTapGesture { model.openSecondary(kind) }
        .help(helpText)
    }

    private var helpText: String {
        switch kind {
        case .timer: return "Timer"
        case .download: return model.downloads.current?.name ?? "Download"
        case .activity: return model.live.current?.title ?? "Live Activity"
        case .privacy: return "Microphone or camera in use"
        case .stopwatch: return "Stopwatch"
        }
    }

    private func ring(_ p: Double, _ c: Color) -> some View {
        ZStack {
            Circle().stroke(c.opacity(0.22), lineWidth: 2.4)
            Circle().trim(from: 0, to: max(0.02, p))
                .stroke(c, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.4), value: p)
        }
        .padding(diameter * 0.12)
    }
}

/// A custom Live Activity in the closed island.
struct CompactActivityView: View {
    @ObservedObject var live: LiveActivityCenter
    let notch: CGSize
    var body: some View {
        let a = live.current
        Wings(notch: notch) {
            HStack(spacing: 6) {
                Image(systemName: a?.icon ?? "sparkles")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(a?.color ?? .white)
                    .symbolEffect(.pulse)
                Text(a?.title ?? "")
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .padding(.leading, 12)
        } right: {
            Group {
                if let p = a?.progress {
                    Text("\(Int(p * 100))%")
                } else {
                    Text(a?.subtitle ?? "")
                }
            }
            .font(.system(size: 11.5, weight: .bold, design: .rounded))
            .foregroundStyle(a?.color ?? .white)
            .lineLimit(1)
            .contentTransition(.numericText())
            .padding(.trailing, 12)
        }
    }
}

/// Live Activities card for the Home tab.
struct LiveActivityCard: View {
    let activity: LiveActivity
    var end: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: activity.icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(activity.color)
                .frame(width: 28, height: 28)
                .background(Circle().fill(activity.color.opacity(0.18)))
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(activity.title).font(.system(size: 12.5, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    Spacer()
                    Button(action: end) { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                        .buttonStyle(.plain).foregroundStyle(.white.opacity(0.4))
                }
                if let p = activity.progress {
                    ProgressView(value: p).tint(activity.color).controlSize(.mini)
                }
                if !activity.subtitle.isEmpty {
                    Text(activity.subtitle).font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.07)))
    }
}

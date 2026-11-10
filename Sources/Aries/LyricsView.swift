import AppKit
import SwiftUI

private final class LyricsWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Shared between the window (which sees raw scroll-wheel events) and the lyrics view.
final class LyricsScrollState: ObservableObject {
    @Published var userOffset: CGFloat = 0
    @Published var lastActivity = Date()
    var lastScroll = Date.distantPast
}

final class LyricsWindowController {
    private let window: LyricsWindow
    private var monitors: [Any] = []
    private let onClose: () -> Void
    private let scroll = LyricsScrollState()
    private var settleTimer: Timer?

    init(music: MusicController, onClose: @escaping () -> Void) {
        self.onClose = onClose
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main!
        window = LyricsWindow(contentRect: screen.frame, styleMask: [.borderless, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isOpaque = true
        window.backgroundColor = .black
        window.isReleasedWhenClosed = false
        window.alphaValue = 0
        window.acceptsMouseMovedEvents = true
        window.setFrame(screen.frame, display: true)

        let close: () -> Void = { [weak self] in self?.close() }
        window.contentView = NSHostingView(rootView: FullScreenPlayer(music: music, clock: music.clock, scroll: scroll, close: close))
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.4
            window.animator().alphaValue = 1
        }
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, e.window === self.window else { return e }
            let m = AppDelegate.shared.music
            switch e.keyCode {
            case 53: self.close(); return nil                 // esc
            case 49: m.playPause(); return nil                // space
            case 124: m.next(); return nil                    // →
            case 123: m.previous(); return nil                // ←
            case 126: m.setVolume(min(100, m.volume + 6)); return nil  // ↑
            case 125: m.setVolume(max(0, m.volume - 6)); return nil    // ↓
            default: return e
            }
        } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .mouseMoved]) { [weak self] e in
            guard let self, e.window === self.window else { return e }
            self.scroll.lastActivity = Date()
            if e.type == .scrollWheel {
                self.scroll.userOffset += e.scrollingDeltaY * (e.hasPreciseScrollingDeltas ? 1 : 12)
                self.scroll.lastScroll = Date()
                self.scheduleSettle()
            }
            return e
        } as Any)
    }

    /// After you stop scrolling, glide back to the line being sung (like Apple Music).
    private func scheduleSettle() {
        settleTimer?.invalidate()
        settleTimer = Timer.scheduledTimer(withTimeInterval: 2.8, repeats: false) { [weak self] _ in
            withAnimation(.spring(response: 0.9, dampingFraction: 0.85)) { self?.scroll.userOffset = 0 }
        }
    }

    func close() {
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors.removeAll()
        settleTimer?.invalidate()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            window.animator().alphaValue = 0
        }, completionHandler: { [window, onClose] in
            window.orderOut(nil)
            onClose()
        })
    }
}

// MARK: - Screen

enum PlayerSide: String { case lyrics, queue, none }

struct FullScreenPlayer: View {
    @ObservedObject var music: MusicController
    @ObservedObject var clock: LyricsClock
    @ObservedObject var scroll: LyricsScrollState
    var close: () -> Void
    @AppStorage("playerSide") private var sideRaw = PlayerSide.lyrics.rawValue

    private var side: PlayerSide { PlayerSide(rawValue: sideRaw) ?? .lyrics }

    var body: some View {
        GeometryReader { geo in
            let compact = geo.size.width < 1100
            let artSize = side == .none ? min(geo.size.height * 0.56, 560) : min(geo.size.height * 0.46, compact ? 320 : 440)
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let idle = ctx.date.timeIntervalSince(scroll.lastActivity) > 3.5 && music.isPlaying
                ZStack {
                    MeshBackdrop(colors: music.palette, accent: music.accent, fallback: music.backdrop)

                    if side == .none {
                        VStack {
                            Spacer(minLength: 0)
                            NowPlayingColumn(music: music, artSize: artSize, side: $sideRaw, idle: idle, centered: true)
                                .frame(width: max(artSize, 460))
                            Spacer(minLength: 0)
                        }
                        .transition(.opacity)
                    } else {
                        HStack(alignment: .center, spacing: compact ? 48 : 96) {
                            NowPlayingColumn(music: music, artSize: artSize, side: $sideRaw, idle: idle, centered: false)
                                .frame(width: artSize)
                            Group {
                                if side == .lyrics {
                                    LyricsColumn(music: music, clock: clock, scroll: scroll)
                                } else {
                                    UpNextColumn(music: music)
                                }
                            }
                            .frame(maxWidth: 760)
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                        }
                        .padding(.horizontal, compact ? 56 : 110)
                        .padding(.vertical, 60)
                    }

                    VStack {
                        HStack {
                            Spacer()
                            Button(action: close) {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 40, height: 40)
                                    .glassCircle()
                            }
                            .buttonStyle(.plain)
                            .keyboardShortcut(.cancelAction)
                            .help("Close (esc)")
                        }
                        Spacer()
                    }
                    .padding(.top, 46)
                    .padding(.trailing, 36)
                    .opacity(idle ? 0 : 1)
                }
                .animation(.easeInOut(duration: 0.6), value: idle)
            }
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.85), value: sideRaw)
        .environment(\.colorScheme, .dark)
        .ignoresSafeArea()
    }
}

// MARK: - Background

/// Slowly flowing mesh gradient built from the album art's colours (macOS 15+),
/// with a blurred-artwork fallback on older systems.
private struct MeshBackdrop: View {
    var colors: [Color]
    var accent: Color
    var fallback: NSImage?

    var body: some View {
        let base = colors.isEmpty ? [accent.opacity(0.6), Color(white: 0.12), accent.opacity(0.35), .black] : colors
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Group {
                if #available(macOS 15.0, *) {
                    MeshGradient(width: 3, height: 3, points: points(t), colors: (0..<9).map { base[$0 % base.count] },
                                 smoothsColors: true)
                } else if let fallback {
                    Image(nsImage: fallback).resizable().scaledToFill().blur(radius: 60)
                        .scaleEffect(1.3 + 0.05 * sin(t / 4))
                        .rotationEffect(.degrees(t * 2))
                } else {
                    LinearGradient(colors: base, startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
        }
        .overlay(Color.black.opacity(0.28))
        .overlay(LinearGradient(colors: [.clear, .black.opacity(0.3)], startPoint: .top, endPoint: .bottom))
        .animation(.easeInOut(duration: 1.5), value: colors.count)
        .ignoresSafeArea()
    }

    private func points(_ t: Double) -> [SIMD2<Float>] {
        func w(_ a: Double, _ s: Double) -> Float { Float(sin(t * s + a) * 0.12) }
        return [
            [0, 0], [0.5 + w(0, 0.21), 0], [1, 0],
            [0, 0.5 + w(1, 0.17)], [0.5 + w(2, 0.23), 0.5 + w(3, 0.19)], [1, 0.5 + w(4, 0.15)],
            [0, 1], [0.5 + w(5, 0.2), 1], [1, 1],
        ]
    }
}

// MARK: - Left column

private struct NowPlayingColumn: View {
    @ObservedObject var music: MusicController
    var artSize: CGFloat
    @Binding var side: String
    var idle: Bool
    var centered: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ArtworkView(image: music.artwork, size: artSize, radius: artSize * 0.04, accent: music.accent)
                .shadow(color: .black.opacity(0.4), radius: 34, y: 18)
                .scaleEffect(music.isPlaying ? 1 : 0.86)
                .animation(.spring(response: 0.55, dampingFraction: 0.68), value: music.isPlaying)
                .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(music.track?.title ?? "Not Playing")
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(music.track?.artist ?? "")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                Spacer()
                LikeButton(music: music, size: 19)
                Menu {
                    Button("Copy Song Link") { music.copyLink() }
                    Button("Open in \(music.source == .appleMusic ? "Music" : "Spotify")") { music.openPlayerApp() }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(.white.opacity(0.14)))
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .buttonStyle(.plain)
                .fixedSize()
            }
            .padding(.top, 26)

            Group {
                ScrubberView(music: music, tint: .white.opacity(0.85), barHeight: 6,
                             font: .system(size: 12, weight: .semibold, design: .rounded),
                             timeColor: .white.opacity(0.5), timesBelow: true)
                    .padding(.top, 16)

                HStack(spacing: 0) {
                    Spacer()
                    Button { music.previous() } label: {
                        Image(systemName: "backward.fill").font(.system(size: 30))
                    }.buttonStyle(PressableStyle(hoverFill: .white.opacity(0.1)))
                    Spacer()
                    Button { music.playPause() } label: {
                        Image(systemName: music.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 44))
                            .contentTransition(.symbolEffect(.replace))
                            .frame(width: 56, height: 52)
                    }.buttonStyle(PressableStyle(hoverFill: .white.opacity(0.1)))
                    Spacer()
                    Button { music.next() } label: {
                        Image(systemName: "forward.fill").font(.system(size: 30))
                    }.buttonStyle(PressableStyle(hoverFill: .white.opacity(0.1)))
                    Spacer()
                }
                .foregroundStyle(.white)
                .padding(.top, 10)

                HStack(spacing: 10) {
                    Image(systemName: "speaker.fill").font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
                    VolumeSlider(music: music)
                    Image(systemName: "speaker.wave.3.fill").font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
                }
                .padding(.top, 14)

                HStack(spacing: 0) {
                    toggle("quote.bubble", on: side == PlayerSide.lyrics.rawValue, help: "Lyrics") {
                        side = side == PlayerSide.lyrics.rawValue ? PlayerSide.none.rawValue : PlayerSide.lyrics.rawValue
                    }
                    Spacer()
                    if music.isSpotify {
                        DeviceMenu(music: music)
                        Spacer()
                    }
                    toggle("list.bullet", on: side == PlayerSide.queue.rawValue, help: "Up Next") {
                        side = side == PlayerSide.queue.rawValue ? PlayerSide.lyrics.rawValue : PlayerSide.queue.rawValue
                        if side == PlayerSide.queue.rawValue { music.loadQueue() }
                    }
                }
                .padding(.top, 18)
                .padding(.horizontal, 24)
            }
            .opacity(idle ? 0 : 1)
        }
    }

    private func toggle(_ icon: String, on: Bool, help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: on ? icon + ".fill" : icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(on ? .black : .white.opacity(0.75))
                .frame(width: 36, height: 36)
                .background(Circle().fill(on ? Color.white.opacity(0.9) : .clear))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct DeviceMenu: View {
    @ObservedObject var music: MusicController
    var body: some View {
        Menu {
            if !music.webConnected {
                Text("Connect Spotify in Settings to switch devices")
            } else if music.devices.isEmpty {
                Text("Looking for devices…")
            } else {
                ForEach(music.devices) { d in
                    Button { music.transfer(to: d) } label: {
                        Label(d.name + (d.isActive ? "  ✓" : ""), systemImage: d.type.lowercased() == "smartphone" ? "iphone" : "hifispeaker.fill")
                    }
                }
            }
        } label: {
            Image(systemName: "hifispeaker.2.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 36, height: 36)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
        .onAppear { music.loadDevices() }
        .help("Play on another device")
    }
}

// MARK: - Up Next

private struct UpNextColumn: View {
    @ObservedObject var music: MusicController
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Up Next")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
            if !music.webConnected {
                Text("Connect Spotify in Settings to see your queue.")
                    .font(.system(size: 17, weight: .medium)).foregroundStyle(.white.opacity(0.6))
            } else if music.upNext.isEmpty {
                Text(music.loadingExtras ? "Loading…" : "Your queue is empty.")
                    .font(.system(size: 17, weight: .medium)).foregroundStyle(.white.opacity(0.6))
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(music.upNext.enumerated()), id: \.offset) { _, t in
                            QueueRow(track: t) { music.play(t) }
                        }
                    }
                }
                .mask(LinearGradient(stops: [.init(color: .black, location: 0.85), .init(color: .clear, location: 1)],
                                     startPoint: .top, endPoint: .bottom))
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 80)
    }
}

private struct QueueRow: View {
    let track: SpotifyWeb.SimpleTrack
    let action: () -> Void
    @ViewState private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                AsyncImage(url: track.artURL) { $0.resizable() } placeholder: { Color.white.opacity(0.1) }
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    Text(track.artist).font(.system(size: 14)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                }
                Spacer()
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(hover ? 0.1 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: - Lyrics

private struct LyricsColumn: View {
    @ObservedObject var music: MusicController
    @ObservedObject var clock: LyricsClock
    @ObservedObject var scroll: LyricsScrollState
    @AppStorage(Prefs.lyricsSize) private var fontSize = 42.0

    var body: some View {
        Group {
            switch music.lyricsState {
            case .loading, .idle:
                ProgressView().controlSize(.large).tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .unavailable:
                VStack(alignment: .leading, spacing: 10) {
                    Text("Lyrics aren't available")
                        .font(.system(size: 30, weight: .bold))
                    Text("for this song yet.")
                        .font(.system(size: 30, weight: .bold))
                        .opacity(0.5)
                }
                .foregroundStyle(.white.opacity(0.7))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            case .loaded:
                if let lyrics = music.lyrics {
                    if lyrics.synced {
                        SyncedLyrics(lyrics: lyrics, music: music, current: clock.lineIndex, fontSize: fontSize, scroll: scroll)
                    } else {
                        PlainLyrics(lyrics: lyrics, fontSize: fontSize)
                    }
                }
            }
        }
        .id(music.track?.id)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.5), value: music.track?.id)
    }
}

private struct RowHeights: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

/// Apple Music–style lyrics: each line springs into place with a small staggered delay,
/// the current line lights up word by word, and the rest are dimmed and softly blurred.
private struct SyncedLyrics: View {
    let lyrics: Lyrics
    @ObservedObject var music: MusicController
    let current: Int?
    let fontSize: Double
    @ObservedObject var scroll: LyricsScrollState
    @ViewState private var heights: [Int: CGFloat] = [:]

    var body: some View {
        GeometryReader { geo in
            let spacing = fontSize * 0.7
            let anchor = geo.size.height * 0.3
            let focus = current ?? -1
            let tops = offsets(spacing: spacing)
            let introDots = (lyrics.lines.first?.time ?? 0) > 4 && current == nil
            let target = anchor - (focus >= 0 ? (tops[focus] ?? 0) : -(introDots ? fontSize * 1.4 : 0))

            ZStack(alignment: .topLeading) {
                if introDots {
                    InterludeDots(start: 0, end: lyrics.lines.first?.time ?? 1, music: music, fontSize: fontSize)
                        .offset(y: anchor)
                        .transition(.opacity.combined(with: .scale(scale: 0.6, anchor: .leading)))
                }
                ForEach(lyrics.lines) { line in
                    LyricRow(line: line, lyrics: lyrics, current: current, music: music, fontSize: fontSize,
                             width: geo.size.width)
                        .background(GeometryReader { g in
                            Color.clear.preference(key: RowHeights.self, value: [line.id: g.size.height])
                        })
                        .offset(y: (tops[line.id] ?? 0) + target + scroll.userOffset)
                        .animation(.spring(response: 0.8, dampingFraction: 0.86)
                            .delay(min(0.45, Double(max(0, line.id - focus + 1)) * 0.045)), value: focus)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .clipped()
            .mask(LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.14),
                .init(color: .black, location: 0.8),
                .init(color: .clear, location: 1),
            ], startPoint: .top, endPoint: .bottom))
            .onPreferenceChange(RowHeights.self) { heights = $0 }
        }
    }

    private func offsets(spacing: CGFloat) -> [Int: CGFloat] {
        var y: CGFloat = 0
        var out: [Int: CGFloat] = [:]
        for l in lyrics.lines {
            out[l.id] = y
            let h = heights[l.id] ?? fontSize * 1.3
            y += (l.isInterlude ? max(h, 1) : h) + spacing
        }
        return out
    }
}

private struct LyricRow: View {
    let line: LyricLine
    let lyrics: Lyrics
    let current: Int?
    @ObservedObject var music: MusicController
    let fontSize: Double
    let width: CGFloat
    @ViewState private var hover = false

    var body: some View {
        let isCurrent = current == line.id
        let distance = abs((current ?? -2) - line.id)
        let end = line.id + 1 < lyrics.lines.count ? lyrics.lines[line.id + 1].time : line.time + 5
        Group {
            if line.isInterlude {
                if isCurrent && end - line.time > 3 {
                    InterludeDots(start: line.time, end: end, music: music, fontSize: fontSize)
                        .transition(.scale(scale: 0.5, anchor: .leading).combined(with: .opacity))
                } else {
                    Color.clear.frame(width: 1, height: 1)
                }
            } else if isCurrent {
                WordFillLine(text: line.text, start: line.time, end: end, music: music, fontSize: fontSize)
                    .frame(width: width, alignment: .leading)
            } else {
                Text(line.text)
                    .font(.system(size: fontSize, weight: .bold))
                    .foregroundStyle(.white.opacity(hover ? 0.6 : (line.id < (current ?? 0) ? 0.3 : 0.38)))
                    .frame(width: width, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .blur(radius: hover ? 0 : min(Double(distance) * 0.7, 3))
            }
        }
        .scaleEffect(isCurrent ? 1 : 0.97, anchor: .leading)
        .padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(.white.opacity(hover && !isCurrent ? 0.07 : 0))
            .padding(.horizontal, -12))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { music.seek(to: line.time) }
        .animation(.spring(response: 0.55, dampingFraction: 0.85), value: isCurrent)
        .animation(.easeOut(duration: 0.15), value: hover)
    }
}

/// The current line: words brighten and lift one by one as they're sung.
/// (LRC lyrics only give line timings, so word timing is estimated across the line.)
private struct WordFillLine: View {
    let text: String
    let start: Double
    let end: Double
    @ObservedObject var music: MusicController
    let fontSize: Double

    var body: some View {
        let words = text.split(separator: " ").map(String.init)
        let weights = words.map { Double($0.count) + 1.5 }
        let total = weights.reduce(0, +)
        let singDuration = max(0.6, min(end - start, 12) * 0.88)

        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !music.isPlaying)) { _ in
            let t = music.position + 0.15
            FlowLayout(hSpacing: fontSize * 0.26, vSpacing: fontSize * 0.08) {
                ForEach(Array(words.enumerated()), id: \.offset) { i, w in
                    let before = weights[..<i].reduce(0, +)
                    let ws = start + singDuration * before / total
                    let wd = singDuration * weights[i] / total
                    let p = max(0, min(1, (t - ws) / max(0.08, wd)))
                    Text(w)
                        .font(.system(size: fontSize, weight: .bold))
                        .foregroundStyle(.white.opacity(0.38 + 0.62 * p))
                        .shadow(color: .white.opacity(0.35 * p * (1 - p) * 4 * 0.6), radius: 10)
                        .offset(y: -2.5 * p)
                }
            }
        }
    }
}

/// Wraps words like a paragraph.
struct FlowLayout: Layout {
    var hSpacing: CGFloat
    var vSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0, x + sz.width > maxW { y += rowH + vSpacing; x = 0; rowH = 0 }
            x += sz.width + hSpacing
            rowH = max(rowH, sz.height)
            widest = max(widest, x - hSpacing)
        }
        return CGSize(width: min(widest, maxW), height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > bounds.minX, x + sz.width > bounds.maxX { y += rowH + vSpacing; x = bounds.minX; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += sz.width + hSpacing
            rowH = max(rowH, sz.height)
        }
    }
}

/// The breathing "• • •" Apple Music shows during instrumental breaks.
private struct InterludeDots: View {
    let start: Double
    let end: Double
    @ObservedObject var music: MusicController
    let fontSize: Double

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in
            let p = max(0, min(1, (music.position - start) / max(0.1, end - start)))
            let breathe = 1 + 0.1 * sin(tl.date.timeIntervalSinceReferenceDate * 2.2)
            HStack(spacing: fontSize * 0.26) {
                ForEach(0..<3, id: \.self) { i in
                    let fill = max(0, min(1, p * 3 - Double(i)))
                    Circle()
                        .fill(.white.opacity(0.28 + 0.72 * fill))
                        .frame(width: fontSize * 0.34, height: fontSize * 0.34)
                }
            }
            .scaleEffect(p > 0.92 ? max(0.2, 1 - (p - 0.92) * 9) : breathe, anchor: .leading)
            .padding(.vertical, fontSize * 0.2)
        }
    }
}

private struct PlainLyrics: View {
    let lyrics: Lyrics
    let fontSize: Double
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: fontSize * 0.45) {
                Text("These lyrics aren't time-synced")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.top, 80)
                ForEach(lyrics.lines) { line in
                    Text(line.text.isEmpty ? " " : line.text)
                        .font(.system(size: fontSize * 0.8, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer(minLength: 200)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

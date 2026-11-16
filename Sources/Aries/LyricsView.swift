import AppKit
import SwiftUI
import AVFoundation

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
        if #available(macOS 14.0, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
        window.orderFrontRegardless()
        window.makeKey()
        NSCursor.setHiddenUntilMouseMoves(true)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.4
            window.animator().alphaValue = 1
        }
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, e.window === self.window else { return e }
            let m = AppDelegate.shared.music
            self.scroll.lastActivity = Date()
            switch e.keyCode {
            case 53: self.close(); return nil                 // esc
            case 49: m.playPause(); return nil                // space
            case 124: m.next(); return nil                    // →
            case 123: m.previous(); return nil                // ←
            case 126: m.setVolume(min(100, m.volume + 6)); return nil  // ↑
            case 125: m.setVolume(max(0, m.volume - 6)); return nil    // ↓
            default: break
            }
            switch e.charactersIgnoringModifiers?.lowercased() {
            case "]": m.nudgeLyrics(by: 0.1); return nil      // lyrics earlier
            case "[": m.nudgeLyrics(by: -0.1); return nil     // lyrics later
            case "=", "+": LyricsPrefs.bumpSize(4); return nil
            case "-": LyricsPrefs.bumpSize(-4); return nil
            case "1": LyricsPrefs.style = .lyrics; return nil
            case "2": LyricsPrefs.style = .vinyl; return nil
            case "3": LyricsPrefs.style = .karaoke; return nil
            case "l": LyricsPrefs.cycleStyle(); return nil
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
        KaraokeMic.shared.stop()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            window.animator().alphaValue = 0
        }, completionHandler: { [window, onClose] in
            window.orderOut(nil)
            onClose()
        })
    }
}

// MARK: - Styles

enum LyricsStyle: String, CaseIterable, Identifiable {
    case lyrics, vinyl, karaoke
    var id: String { rawValue }
    var title: String {
        switch self {
        case .lyrics: return "Lyrics"
        case .vinyl: return "Vinyl"
        case .karaoke: return "Karaoke"
        }
    }
    var icon: String {
        switch self {
        case .lyrics: return "quote.bubble.fill"
        case .vinyl: return "opticaldisc.fill"
        case .karaoke: return "music.mic"
        }
    }
}

enum LyricsPrefs {
    static var style: LyricsStyle {
        get { LyricsStyle(rawValue: Prefs.string(Prefs.lyricsStyle)) ?? .lyrics }
        set { withAnimation(.spring(response: 0.7, dampingFraction: 0.85)) { UserDefaults.standard.set(newValue.rawValue, forKey: Prefs.lyricsStyle) } }
    }
    static func cycleStyle() {
        let all = LyricsStyle.allCases
        style = all[((all.firstIndex(of: style) ?? 0) + 1) % all.count]
    }
    static func bumpSize(_ d: Double) {
        let v = min(64, max(28, Prefs.double(Prefs.lyricsSize) + d))
        withAnimation(.spring) { UserDefaults.standard.set(v, forKey: Prefs.lyricsSize) }
    }
}

// MARK: - Screen

enum PlayerSide: String { case lyrics, queue, artist, album, none }

struct FullScreenPlayer: View {
    @ObservedObject var music: MusicController
    @ObservedObject var clock: LyricsClock
    @ObservedObject var scroll: LyricsScrollState
    var close: () -> Void
    @AppStorage("playerSide") private var sideRaw = PlayerSide.lyrics.rawValue
    @AppStorage(Prefs.lyricsStyle) private var styleRaw = LyricsStyle.lyrics.rawValue

    private var side: PlayerSide { PlayerSide(rawValue: sideRaw) ?? .lyrics }
    private var style: LyricsStyle { LyricsStyle(rawValue: styleRaw) ?? .lyrics }

    var body: some View {
        GeometryReader { geo in
            let compact = geo.size.width < 1100
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let idle = ctx.date.timeIntervalSince(scroll.lastActivity) > 3.5 && music.isPlaying
                ZStack {
                    MeshBackdrop(colors: music.palette, accent: music.accent, fallback: music.backdrop,
                                 energy: style == .karaoke ? 1.6 : 1)

                    Group {
                        switch style {
                        case .karaoke:
                            KaraokeView(music: music, clock: clock, idle: idle)
                        case .lyrics, .vinyl:
                            standard(geo: geo, compact: compact, idle: idle)
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    .id(style)

                    TopBar(music: music, style: $styleRaw, close: close)
                        .opacity(idle ? 0 : 1)
                }
                .animation(.easeInOut(duration: 0.6), value: idle)
            }
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.85), value: sideRaw)
        .animation(.spring(response: 0.7, dampingFraction: 0.85), value: styleRaw)
        .environment(\.colorScheme, .dark)
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func standard(geo: GeometryProxy, compact: Bool, idle: Bool) -> some View {
        let vinyl = style == .vinyl
        let artSize: CGFloat = side == .none
            ? min(geo.size.height * 0.56, 560)
            : min(geo.size.height * (vinyl ? 0.42 : 0.46), compact ? 320 : (vinyl ? 400 : 440))
        if side == .none {
            VStack {
                Spacer(minLength: 0)
                NowPlayingColumn(music: music, artSize: artSize, vinyl: vinyl, side: $sideRaw, idle: idle, centered: true)
                    .frame(width: max(vinyl ? artSize * 1.45 : artSize, 460))
                Spacer(minLength: 0)
            }
            .transition(.opacity)
        } else {
            HStack(alignment: .center, spacing: compact ? 48 : 96) {
                NowPlayingColumn(music: music, artSize: artSize, vinyl: vinyl, side: $sideRaw, idle: idle, centered: false)
                    .frame(width: vinyl ? artSize * 1.45 : artSize)
                Group {
                    switch side {
                    case .lyrics, .none: LyricsColumn(music: music, clock: clock, scroll: scroll)
                    case .queue: UpNextColumn(music: music)
                    case .artist: ArtistColumn(music: music)
                    case .album: AlbumColumn(music: music)
                    }
                }
                .frame(maxWidth: 760)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
            .padding(.horizontal, compact ? 56 : 110)
            .padding(.vertical, 60)
        }
    }
}

// MARK: - Top bar (style switcher, timing, text size)

private struct TopBar: View {
    @ObservedObject var music: MusicController
    @Binding var style: String
    var close: () -> Void
    @AppStorage(Prefs.lyricsSize) private var fontSize = 42.0

    var body: some View {
        VStack {
            HStack(spacing: 12) {
                // Style switcher
                HStack(spacing: 2) {
                    ForEach(LyricsStyle.allCases) { s in
                        let on = style == s.rawValue
                        Button { LyricsPrefs.style = s } label: {
                            Label(s.title, systemImage: s.icon)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(on ? .black : .white.opacity(0.85))
                                .padding(.horizontal, 13).frame(height: 32)
                                .background(Capsule().fill(on ? Color.white : .clear))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .help("\(s.title) (\((LyricsStyle.allCases.firstIndex(of: s) ?? 0) + 1))")
                    }
                }
                .padding(3)
                .glassCapsule()

                Spacer()

                if music.lyrics?.synced == true {
                    TimingControl(music: music)
                }

                HStack(spacing: 0) {
                    Button { LyricsPrefs.bumpSize(-4) } label: {
                        Image(systemName: "textformat.size.smaller").frame(width: 34, height: 32)
                    }.buttonStyle(.plain).help("Smaller text (−)")
                    Button { LyricsPrefs.bumpSize(4) } label: {
                        Image(systemName: "textformat.size.larger").frame(width: 34, height: 32)
                    }.buttonStyle(.plain).help("Larger text (+)")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .padding(3)
                .glassCapsule()

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
        .padding(.top, 40)
        .padding(.horizontal, 36)
    }
}

/// Nudge lyrics earlier/later when a song's lyrics are off. Remembered per song.
private struct TimingControl: View {
    @ObservedObject var music: MusicController
    var body: some View {
        HStack(spacing: 0) {
            Button { music.nudgeLyrics(by: -0.1) } label: {
                Image(systemName: "minus").frame(width: 30, height: 32)
            }.buttonStyle(.plain).help("Lyrics later ([)")
            Button { music.resetLyricsOffset() } label: {
                VStack(spacing: 0) {
                    Text(label).font(.system(size: 12.5, weight: .bold, design: .rounded)).monospacedDigit()
                        .contentTransition(.numericText())
                    Text("timing").font(.system(size: 8.5, weight: .semibold)).opacity(0.6)
                }
                .frame(minWidth: 54)
            }
            .buttonStyle(.plain)
            .help("Lyrics ahead or behind? Use − and +. Click to reset.")
            Button { music.nudgeLyrics(by: 0.1) } label: {
                Image(systemName: "plus").frame(width: 30, height: 32)
            }.buttonStyle(.plain).help("Lyrics earlier (])")
        }
        .font(.system(size: 13, weight: .bold))
        .foregroundStyle(.white.opacity(0.9))
        .padding(3)
        .glassCapsule(tint: music.songOffset != 0 ? music.accent.opacity(0.35) : nil)
        .animation(.spring, value: music.songOffset)
    }
    private var label: String {
        let v = music.songOffset
        return v == 0 ? "In sync" : String(format: "%@%.1fs", v > 0 ? "+" : "−", abs(v))
    }
}

// MARK: - Background

/// Slowly flowing mesh gradient built from the album art's colours (macOS 15+),
/// with a blurred-artwork fallback on older systems.
private struct MeshBackdrop: View {
    var colors: [Color]
    var accent: Color
    var fallback: NSImage?
    var energy: Double = 1

    var body: some View {
        let base = colors.isEmpty ? [accent.opacity(0.6), Color(white: 0.12), accent.opacity(0.35), .black] : colors
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: A11y.reduceMotion)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate * energy
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

// MARK: - Artwork: animated, or a spinning record

/// Album art that slowly breathes and drifts while music plays (like Apple Music's motion artwork).
private struct LivingArtwork: View {
    @ObservedObject var music: MusicController
    let size: CGFloat
    @AppStorage(Prefs.animatedArt) private var animated = true

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !music.isPlaying || !animated || A11y.reduceMotion)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let on = music.isPlaying && animated && !A11y.reduceMotion
            ZStack {
                if let img = music.artwork {
                    Image(nsImage: img).resizable().interpolation(.high).scaledToFill()
                        .scaleEffect(on ? 1.07 + 0.03 * sin(t / 5) : 1)
                        .offset(x: on ? size * 0.018 * sin(t / 7) : 0, y: on ? size * 0.018 * cos(t / 6) : 0)
                } else {
                    ArtworkView(image: nil, size: size, radius: size * 0.04, accent: music.accent)
                }
                // Moving light sheen.
                if on {
                    LinearGradient(colors: [.clear, .white.opacity(0.10), .clear],
                                   startPoint: UnitPoint(x: -1 + (t / 9).truncatingRemainder(dividingBy: 3), y: 0),
                                   endPoint: UnitPoint(x: (t / 9).truncatingRemainder(dividingBy: 3), y: 1))
                        .blendMode(.plusLighter)
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.04, style: .continuous))
            .rotation3DEffect(.degrees(on ? 3 * sin(t / 4) : 0), axis: (x: 0.4, y: 1, z: 0), perspective: 0.6)
        }
        .id(music.track?.id)
        .transition(.asymmetric(insertion: .scale(scale: 0.85).combined(with: .opacity),
                                removal: .opacity))
        .animation(.spring(response: 0.6, dampingFraction: 0.75), value: music.track?.id)
    }
}

/// A record sliding out of its sleeve, spinning at 33⅓ while it plays, with a tonearm.
struct VinylRecord: View {
    @ObservedObject var music: MusicController
    let size: CGFloat
    @ViewState private var out = false

    var body: some View {
        let disc = size * 0.96
        ZStack(alignment: .leading) {
            // The record (behind the sleeve, slides out to the right)
            TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !music.isPlaying)) { _ in
                RecordDisc(art: music.artwork, accent: music.accent, size: disc)
                    .rotationEffect(.degrees(music.position * 200))     // 33⅓ rpm
            }
            .frame(width: disc, height: disc)
            .offset(x: out ? size * 0.47 : size * 0.05)
            .shadow(color: .black.opacity(0.5), radius: 20, x: 6, y: 10)

            // The sleeve (album cover)
            ArtworkView(image: music.artwork, size: size, radius: size * 0.015, accent: music.accent)
                .overlay(LinearGradient(colors: [.white.opacity(0.12), .clear, .black.opacity(0.18)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.015)))
                .shadow(color: .black.opacity(0.45), radius: 26, y: 14)

            // Tonearm
            Tonearm(length: size * 0.78)
                .rotationEffect(.degrees(music.isPlaying && out ? 22 : 0), anchor: UnitPoint(x: 0.5, y: 0.06))
                .offset(x: size * 0.47 + disc * 0.86, y: -size * 0.06)
                .animation(.spring(response: 0.9, dampingFraction: 0.7).delay(music.isPlaying ? 0.25 : 0), value: music.isPlaying)
                .opacity(out ? 1 : 0)
        }
        .frame(width: size * 1.45, height: size, alignment: .leading)
        .onAppear {
            withAnimation(.spring(response: 1.1, dampingFraction: 0.78).delay(0.25)) { out = true }
        }
        .onChange(of: music.track?.id) { _, _ in
            // New song: slip the record back in and out again.
            withAnimation(.easeIn(duration: 0.3)) { out = false }
            withAnimation(.spring(response: 1.0, dampingFraction: 0.78).delay(0.45)) { out = true }
        }
    }
}

struct RecordDisc: View {
    let art: NSImage?
    let accent: Color
    let size: CGFloat
    var body: some View {
        ZStack {
            Circle().fill(Color(white: 0.04))
            // Grooves
            ForEach(0..<18, id: \.self) { i in
                Circle().stroke(Color.white.opacity(i % 3 == 0 ? 0.07 : 0.035), lineWidth: 0.8)
                    .padding(size * (0.04 + Double(i) * 0.0165))
            }
            // Label (the album art)
            Group {
                if let art { Image(nsImage: art).resizable().scaledToFill() } else { accent.opacity(0.7) }
            }
            .frame(width: size * 0.36, height: size * 0.36)
            .clipShape(Circle())
            .overlay(Circle().stroke(.black.opacity(0.4), lineWidth: 2))
            Circle().fill(Color(white: 0.85)).frame(width: size * 0.025, height: size * 0.025)
        }
        // Light reflecting off the vinyl stays put while the record turns.
        .overlay(
            AngularGradient(colors: [.clear, .white.opacity(0.13), .clear, .clear, .white.opacity(0.09), .clear, .clear],
                            center: .center)
                .clipShape(Circle())
                .allowsHitTesting(false)
        )
    }
}

struct Tonearm: View {
    let length: CGFloat
    var body: some View {
        ZStack(alignment: .top) {
            Capsule()
                .fill(LinearGradient(colors: [Color(white: 0.92), Color(white: 0.6)], startPoint: .leading, endPoint: .trailing))
                .frame(width: length * 0.035, height: length * 0.86)
                .offset(y: length * 0.04)
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(white: 0.75))
                .frame(width: length * 0.075, height: length * 0.14)
                .offset(x: -length * 0.012, y: length * 0.86)
            Circle()
                .fill(RadialGradient(colors: [Color(white: 0.95), Color(white: 0.45)], center: .topLeading, startRadius: 1, endRadius: length * 0.09))
                .frame(width: length * 0.13, height: length * 0.13)
        }
        .frame(width: length * 0.13, height: length, alignment: .top)
        .shadow(color: .black.opacity(0.5), radius: 8, x: 4, y: 6)
    }
}

// MARK: - Left column

private struct NowPlayingColumn: View {
    @ObservedObject var music: MusicController
    var artSize: CGFloat
    var vinyl: Bool
    @Binding var side: String
    var idle: Bool
    var centered: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if vinyl {
                    VinylRecord(music: music, size: artSize)
                } else {
                    LivingArtwork(music: music, size: artSize)
                        .shadow(color: .black.opacity(0.4), radius: 34, y: 18)
                        .scaleEffect(music.isPlaying ? 1 : 0.86)
                        .animation(.spring(response: 0.55, dampingFraction: 0.68), value: music.isPlaying)
                }
            }
            .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(music.track?.title ?? "Not Playing")
                            .font(.system(size: 21, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Button { open(.artist) } label: {
                            Text(music.track?.artist ?? "")
                                .font(.system(size: 18, weight: .regular))
                                .foregroundStyle(.white.opacity(0.6))
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .help("About the artist")
                    }
                    Spacer()
                    LikeButton(music: music, size: 19)
                    Menu {
                        if music.webConnected {
                            Menu("Add to Playlist") {
                                let mine = music.playlists.filter(\.mine)
                                if mine.isEmpty { Text("Loading playlists…") }
                                ForEach(mine) { p in Button(p.name) { music.addCurrent(to: p) } }
                            }
                            Button("Go to Artist") { open(.artist) }
                            Button("Go to Album") { open(.album) }
                            Divider()
                        }
                        Button("Copy Song Link") { music.copyLink() }
                        if let l = music.lyrics, !l.lines.isEmpty {
                            Button("Copy Lyrics") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(l.lines.map(\.text).joined(separator: "\n"), forType: .string)
                            }
                        }
                        Button("Open in \(music.source == .appleMusic ? "Music" : "Spotify")") { music.openPlayerApp() }
                        Divider()
                        Button("Reset Lyrics Timing") { music.resetLyricsOffset() }
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
                    .onAppear { music.loadPlaylists() }
                }
                .padding(.top, 26)

                Group {
                    ScrubberView(music: music, tint: .white.opacity(0.85), barHeight: 6,
                                 font: .system(size: 12, weight: .semibold, design: .rounded),
                                 timeColor: .white.opacity(0.5), timesBelow: true)
                        .padding(.top, 16)

                    TransportControls(music: music, big: true)
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
                        if music.webConnected {
                            toggle("music.mic.circle", on: side == PlayerSide.artist.rawValue, help: "Artist") { open(.artist) }
                            Spacer()
                            toggle("square.stack", on: side == PlayerSide.album.rawValue, help: "Album") { open(.album) }
                            Spacer()
                        }
                        if music.isSpotify {
                            DeviceMenu(music: music)
                            Spacer()
                        }
                        toggle("list.bullet", on: side == PlayerSide.queue.rawValue, help: "Up Next") { open(.queue) }
                    }
                    .padding(.top, 18)
                    .padding(.horizontal, 24)
                }
                .opacity(idle ? 0 : 1)
            }
            .frame(width: artSize)
            .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
        }
    }

    /// Opens a side panel, or goes back to lyrics if it's already open.
    private func open(_ s: PlayerSide) {
        if side == s.rawValue { side = PlayerSide.lyrics.rawValue; return }
        side = s.rawValue
        switch s {
        case .queue: music.loadQueue()
        case .artist: music.loadArtist()
        case .album: music.loadAlbum()
        default: break
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

private struct TransportControls: View {
    @ObservedObject var music: MusicController
    var big: Bool
    var body: some View {
        HStack(spacing: 0) {
            Spacer()
            Button { music.previous() } label: {
                Image(systemName: "backward.fill").font(.system(size: big ? 30 : 22))
            }.buttonStyle(PressableStyle(hoverFill: .white.opacity(0.1)))
            Spacer()
            Button { music.playPause() } label: {
                Image(systemName: music.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: big ? 44 : 30))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: big ? 56 : 40, height: big ? 52 : 38)
            }.buttonStyle(PressableStyle(hoverFill: .white.opacity(0.1)))
            Spacer()
            Button { music.next() } label: {
                Image(systemName: "forward.fill").font(.system(size: big ? 30 : 22))
            }.buttonStyle(PressableStyle(hoverFill: .white.opacity(0.1)))
            Spacer()
        }
        .foregroundStyle(.white)
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
                            QueueRow(track: t, music: music) { music.play(t) }
                        }
                        if !music.recent.isEmpty {
                            Text("Recently Played")
                                .font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                                .padding(.top, 22).padding(.bottom, 4)
                            ForEach(Array(music.recent.prefix(12).enumerated()), id: \.offset) { _, t in
                                QueueRow(track: t, music: music) { music.play(t) }
                            }
                        }
                    }
                }
                .mask(LinearGradient(stops: [.init(color: .black, location: 0.85), .init(color: .clear, location: 1)],
                                     startPoint: .top, endPoint: .bottom))
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 80)
        .onAppear { music.loadQueue() }
    }
}

private struct QueueRow: View {
    let track: SpotifyWeb.SimpleTrack
    var music: MusicController? = nil
    var number: Int? = nil
    let action: () -> Void
    @ViewState private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                if let number {
                    Text("\(number)").font(.system(size: 15, weight: .semibold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(.white.opacity(0.45)).frame(width: 28)
                } else {
                    AsyncImage(url: track.artURL) { $0.resizable() } placeholder: { Color.white.opacity(0.1) }
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    Text(track.artist).font(.system(size: 14)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                }
                Spacer()
                if hover, let music {
                    Button { music.addToQueue(track) } label: {
                        Image(systemName: "text.line.last.and.arrowtriangle.forward")
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
                            .frame(width: 34, height: 34).background(Circle().fill(.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    .help("Play Next")
                    .transition(.opacity)
                }
                if track.duration > 0 {
                    Text(String(format: "%d:%02d", Int(track.duration) / 60, Int(track.duration) % 60)).font(.system(size: 13).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(hover ? 0.1 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
        .contextMenu {
            Button("Play") { action() }
            if let music { Button("Play Next") { music.addToQueue(track) } }
            Button("Copy Song Link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("https://open.spotify.com/track/\(track.id)", forType: .string)
            }
        }
    }
}

// MARK: - Artist & Album (Spotify)

private struct ArtistColumn: View {
    @ObservedObject var music: MusicController
    var body: some View {
        Group {
            if let a = music.artistInfo {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 22) {
                            AsyncImage(url: a.imageURL) { $0.resizable().scaledToFill() } placeholder: { Color.white.opacity(0.1) }
                                .frame(width: 150, height: 150)
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
                            VStack(alignment: .leading, spacing: 8) {
                                Text("ARTIST").font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.5))
                                Text(a.name).font(.system(size: 40, weight: .heavy)).foregroundStyle(.white).lineLimit(2)
                                    .minimumScaleFactor(0.6)
                                HStack(spacing: 10) {
                                    if let f = a.followers {
                                        Text("\(f.formatted(.number.notation(.compactName))) followers")
                                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
                                    }
                                    if let following = a.following {
                                        Button { music.toggleFollow() } label: {
                                            Text(following ? "Following" : "Follow")
                                                .font(.system(size: 13, weight: .bold))
                                                .foregroundStyle(following ? .white : .black)
                                                .padding(.horizontal, 16).frame(height: 30)
                                                .background(Capsule().fill(following ? Color.white.opacity(0.15) : .white))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                if !a.genres.isEmpty {
                                    Text(a.genres.prefix(3).map { $0.capitalized }.joined(separator: " · "))
                                        .font(.system(size: 13)).foregroundStyle(.white.opacity(0.5))
                                }
                            }
                        }
                        if !a.top.isEmpty {
                            Text("Popular").font(.system(size: 22, weight: .bold)).foregroundStyle(.white).padding(.top, 6)
                            LazyVStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(a.top.enumerated()), id: \.offset) { _, t in
                                    QueueRow(track: t, music: music) { music.play(t, inContext: a.uri) }
                                }
                            }
                        }
                        Button { NSWorkspace.shared.open(URL(string: a.uri)!) } label: {
                            Label("Open in Spotify", systemImage: "arrow.up.right").font(.system(size: 13, weight: .semibold))
                        }
                        .buttonStyle(.plain).foregroundStyle(.white.opacity(0.7))
                        Spacer(minLength: 60)
                    }
                    .padding(.top, 90)
                }
                .mask(LinearGradient(stops: [.init(color: .black, location: 0.85), .init(color: .clear, location: 1)],
                                     startPoint: .top, endPoint: .bottom))
            } else {
                SpotifyEmpty(music: music, what: "artist")
            }
        }
        .onChange(of: music.track?.id) { _, _ in music.loadArtist() }
        // Opening the player straight onto this page (or reopening it) must load it too.
        .onAppear { music.loadArtist() }
    }
}

private struct AlbumColumn: View {
    @ObservedObject var music: MusicController
    var body: some View {
        Group {
            if let a = music.albumInfo {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .bottom, spacing: 20) {
                            AsyncImage(url: a.imageURL) { $0.resizable().scaledToFill() } placeholder: { Color.white.opacity(0.1) }
                                .frame(width: 130, height: 130)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("ALBUM").font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.5))
                                Text(a.name).font(.system(size: 30, weight: .heavy)).foregroundStyle(.white).lineLimit(2)
                                    .minimumScaleFactor(0.6)
                                Text([a.year, "\(a.tracks.count) songs", a.label].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.system(size: 13)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                            }
                        }
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(a.tracks.enumerated()), id: \.offset) { i, t in
                                QueueRow(track: t, music: music, number: i + 1) { music.play(t, inContext: a.uri) }
                                    .overlay(alignment: .leading) {
                                        if music.track?.spotifyID == t.id {
                                            Image(systemName: "waveform").foregroundStyle(music.accent)
                                                .symbolEffect(.variableColor.iterative, isActive: music.isPlaying)
                                                .frame(width: 28).padding(.leading, 8)
                                                .background(Color.clear)
                                        }
                                    }
                            }
                        }
                        Spacer(minLength: 60)
                    }
                    .padding(.top, 90)
                }
                .mask(LinearGradient(stops: [.init(color: .black, location: 0.85), .init(color: .clear, location: 1)],
                                     startPoint: .top, endPoint: .bottom))
            } else {
                SpotifyEmpty(music: music, what: "album")
            }
        }
        .onChange(of: music.track?.id) { _, _ in music.loadAlbum() }
        .onAppear { music.loadAlbum() }
    }
}

private struct SpotifyEmpty: View {
    @ObservedObject var music: MusicController
    let what: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if music.loadingSpotify {
                ProgressView().controlSize(.large).tint(.white)
            } else if !music.webConnected {
                Text("Connect Spotify").font(.system(size: 28, weight: .bold))
                Text("Connect your Spotify account in Settings › Music Connections to see the \(what), add songs to playlists and more.")
                    .font(.system(size: 16)).opacity(0.6)
                Button("Open Settings") { AppDelegate.shared.openSettings(pane: "spotify") }.padding(.top, 6)
            } else {
                Text("Couldn't find this \(what) on Spotify").font(.system(size: 24, weight: .bold)).opacity(0.7)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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
                WordFillLine(text: line.text, timedWords: line.words, start: line.time, end: end, music: music,
                             fontSize: fontSize)
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
        .onTapGesture { music.seek(to: max(0, line.time - music.songOffset - Prefs.double(Prefs.lyricsOffset))) }
        .contextMenu {
            if !line.isInterlude {
                Button("Copy Line") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(line.text, forType: .string)
                }
                Button("Play From Here") { music.seek(to: max(0, line.time - music.songOffset - Prefs.double(Prefs.lyricsOffset))) }
            }
        }
        .animation(.spring(response: 0.55, dampingFraction: 0.85), value: isCurrent)
        .animation(.easeOut(duration: 0.15), value: hover)
    }
}

/// When each word of a line starts and how long it's sung for.
/// Uses real word timing when the lyrics have it; otherwise estimates it from how long the words are,
/// at a natural singing pace (so a line followed by a long instrumental doesn't crawl).
enum WordTiming {
    static func spans(text: String, timed: [LyricWord]?, start: Double, end: Double) -> [(word: String, start: Double, dur: Double)] {
        if let tw = timed, !tw.isEmpty {
            return tw.enumerated().map { i, w in
                let next = i + 1 < tw.count ? tw[i + 1].time : min(end, w.time + max(0.35, Double(w.text.count) * 0.09))
                return (w.text, w.time, max(0.08, next - w.time))
            }
        }
        let words = text.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        let weights = words.map { Double($0.count) + 1.5 }
        let total = weights.reduce(0, +)
        let chars = Double(text.count)
        let natural = max(0.9, chars * 0.105 + 0.35)
        let sing = max(0.6, min((end - start) * 0.92, natural))
        var t = start
        return words.enumerated().map { i, w in
            let d = sing * weights[i] / total
            defer { t += d }
            return (w, t, d)
        }
    }
}

/// The current line: each word fills left-to-right with light as it's sung (Apple Music style).
private struct WordFillLine: View {
    let text: String
    var timedWords: [LyricWord]? = nil
    let start: Double
    let end: Double
    @ObservedObject var music: MusicController
    let fontSize: Double
    var fill: Color = .white
    var base: Color = .white.opacity(0.32)
    var centered = false

    var body: some View {
        let spans = WordTiming.spans(text: text, timed: timedWords, start: start, end: end)
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !music.isPlaying)) { _ in
            let t = music.lyricsTime + 0.08
            FlowLayout(hSpacing: fontSize * 0.26, vSpacing: fontSize * 0.08, centered: centered) {
                ForEach(Array(spans.enumerated()), id: \.offset) { _, s in
                    let p = max(0, min(1, (t - s.start) / s.dur))
                    SweptWord(word: s.word, p: p, fontSize: fontSize, fill: fill, base: base)
                }
            }
        }
    }
}

private struct SweptWord: View {
    let word: String
    let p: Double
    let fontSize: Double
    let fill: Color
    let base: Color

    var body: some View {
        let font = Font.system(size: fontSize, weight: .bold)
        Text(word).font(font).foregroundStyle(base)
            .overlay {
                Text(word).font(font).foregroundStyle(fill)
                    .mask(
                        LinearGradient(colors: [.black, .clear],
                                       startPoint: UnitPoint(x: p * 1.25 - 0.25, y: 0.5),
                                       endPoint: UnitPoint(x: p * 1.25, y: 0.5))
                    )
                    .shadow(color: fill.opacity(0.55 * p * (1 - p) * 4 * 0.6), radius: 12)
            }
            .offset(y: -2.5 * p)
            .scaleEffect(1 + 0.025 * p * (1 - p) * 4, anchor: .bottom)
    }
}

/// Wraps words like a paragraph.
struct FlowLayout: Layout {
    var hSpacing: CGFloat
    var vSpacing: CGFloat
    var centered = false

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
        return CGSize(width: centered ? (proposal.width ?? widest) : min(widest, maxW), height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        // Break into rows first so rows can be centred.
        var rows: [[(Subviews.Element, CGSize)]] = [[]]
        var x: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0, x + sz.width > bounds.width { rows.append([]); x = 0 }
            rows[rows.count - 1].append((s, sz))
            x += sz.width + hSpacing
        }
        var y = bounds.minY
        for row in rows {
            let rowW = row.reduce(0) { $0 + $1.1.width } + hSpacing * CGFloat(max(0, row.count - 1))
            var cx = centered ? bounds.minX + (bounds.width - rowW) / 2 : bounds.minX
            let rowH = row.map(\.1.height).max() ?? 0
            for (s, sz) in row {
                s.place(at: CGPoint(x: cx, y: y), proposal: .unspecified)
                cx += sz.width + hSpacing
            }
            y += rowH + vSpacing
        }
    }
}

/// The breathing "• • •" Apple Music shows during instrumental breaks.
private struct InterludeDots: View {
    let start: Double
    let end: Double
    @ObservedObject var music: MusicController
    let fontSize: Double
    var color: Color = .white

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in
            let p = max(0, min(1, (music.lyricsTime - start) / max(0.1, end - start)))
            let breathe = 1 + 0.1 * sin(tl.date.timeIntervalSinceReferenceDate * 2.2)
            HStack(spacing: fontSize * 0.26) {
                ForEach(0..<3, id: \.self) { i in
                    let fill = max(0, min(1, p * 3 - Double(i)))
                    Circle()
                        .fill(color.opacity(0.28 + 0.72 * fill))
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

// MARK: - Karaoke

/// Listens to your microphone while you sing along and scores how much of each line you sang.
/// Audio never leaves the Mac and nothing is recorded; it's only a loudness meter.
final class KaraokeMic: ObservableObject {
    static let shared = KaraokeMic()
    @Published private(set) var running = false
    @Published private(set) var level: Double = 0
    @Published private(set) var score = 0
    @Published private(set) var denied = false
    private var engine: AVAudioEngine?
    private var sungTime = 0.0, lineTime = 0.0
    private var lastTick = Date()

    func toggle() { running ? stop() : start() }

    func start() {
        AVCaptureDevice.requestAccess(for: .audio) { ok in
            DispatchQueue.main.async {
                guard ok else { self.denied = true; return }
                self.denied = false
                let e = AVAudioEngine()
                let input = e.inputNode
                let fmt = input.outputFormat(forBus: 0)
                guard fmt.sampleRate > 0 else { return }
                input.installTap(onBus: 0, bufferSize: 1024, format: fmt) { [weak mic = self] buf, _ in
                    guard let ch = buf.floatChannelData?[0] else { return }
                    let n = Int(buf.frameLength)
                    var sum: Float = 0
                    for i in 0..<n { sum += ch[i] * ch[i] }
                    let rms = sqrt(sum / Float(max(1, n)))
                    let db = 20 * log10(max(rms, 1e-6))
                    let lvl = Double(max(0, min(1, (db + 52) / 40)))
                    DispatchQueue.main.async { if let mic { mic.level = mic.level * 0.6 + lvl * 0.4 } }
                }
                do { try e.start(); self.engine = e; self.running = true; self.reset() } catch { self.engine = nil }
            }
        }
    }

    func stop() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        if running { running = false }
        level = 0
    }

    func reset() { sungTime = 0; lineTime = 0; score = 0; lastTick = Date() }

    /// Called ~10×/s while a line is being sung.
    func tick(lineActive: Bool) {
        let now = Date()
        let dt = min(0.5, now.timeIntervalSince(lastTick))
        lastTick = now
        guard running, lineActive else { return }
        lineTime += dt
        if level > 0.28 { sungTime += dt }
        let s = Int((sungTime / max(1, lineTime) * 100).rounded())
        if s != score { score = s }
    }
}

/// Big centred two-line karaoke: the line being sung sweeps with colour, the next one waits below,
/// and a countdown appears before the singing comes back in.
private struct KaraokeView: View {
    @ObservedObject var music: MusicController
    @ObservedObject var clock: LyricsClock
    var idle: Bool
    @ObservedObject private var mic = KaraokeMic.shared
    @AppStorage(Prefs.lyricsSize) private var fontSize = 42.0

    var body: some View {
        let size = fontSize * 1.3
        VStack(spacing: 0) {
            header.padding(.top, 104)
            Spacer(minLength: 20)
            Group {
                if let lyrics = music.lyrics, lyrics.synced {
                    lines(lyrics, size: size)
                } else if music.lyricsState == .loading {
                    ProgressView().controlSize(.large).tint(.white)
                } else {
                    Text(music.lyrics == nil ? "No lyrics for this song" : "Karaoke needs time-synced lyrics")
                        .font(.system(size: 30, weight: .bold)).foregroundStyle(.white.opacity(0.6))
                }
            }
            .frame(maxWidth: 1100)
            .padding(.horizontal, 60)
            Spacer(minLength: 20)
            footer.padding(.bottom, 54).opacity(idle ? 0.25 : 1)
        }
        .onChange(of: music.track?.id) { _, _ in mic.reset() }
        .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
            let line = clock.lineIndex.flatMap { i in music.lyrics.map { $0.lines[i] } }
            mic.tick(lineActive: music.isPlaying && line.map { !$0.isInterlude } == true)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ArtworkView(image: music.artwork, size: 54, radius: 9, accent: music.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(music.track?.title ?? "Not Playing").font(.system(size: 19, weight: .bold)).foregroundStyle(.white)
                Text(music.track?.artist ?? "").font(.system(size: 15)).foregroundStyle(.white.opacity(0.6))
            }
            .lineLimit(1)
        }
    }

    @ViewBuilder
    private func lines(_ lyrics: Lyrics, size: Double) -> some View {
        let idx = clock.lineIndex
        let sungIdx: Int? = {
            guard let i = idx else { return nil }
            return lyrics.lines[i].isInterlude ? nil : i
        }()
        let nextIdx = lyrics.lines.indices.first { $0 > (idx ?? -1) && !lyrics.lines[$0].isInterlude }
        let gapStart: Double = idx.map { lyrics.lines[$0].time } ?? 0
        let showCount = sungIdx == nil && nextIdx.map { lyrics.lines[$0].time - gapStart >= 4 } == true

        VStack(spacing: size * 0.5) {
            ZStack {
                if let i = sungIdx {
                    let l = lyrics.lines[i]
                    let end = i + 1 < lyrics.lines.count ? lyrics.lines[i + 1].time : l.time + 5
                    WordFillLine(text: l.text, timedWords: l.words, start: l.time, end: end, music: music,
                                 fontSize: size, fill: Color(red: 0.38, green: 0.92, blue: 1.0),
                                 base: .white, centered: true)
                        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                                removal: .move(edge: .top).combined(with: .opacity)))
                        .id(i)
                } else if showCount, let n = nextIdx {
                    Countdown(target: lyrics.lines[n].time, music: music, size: size)
                        .transition(.opacity)
                }
            }
            .frame(minHeight: size * 1.4)

            if let n = (sungIdx != nil ? lyrics.lines.indices.first { $0 > sungIdx! && !lyrics.lines[$0].isInterlude } : nextIdx) {
                Text(lyrics.lines[n].text)
                    .font(.system(size: size * 0.72, weight: .bold))
                    .foregroundStyle(.white.opacity(0.45))
                    .multilineTextAlignment(.center)
                    .id("next-\(n)")
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                            removal: .opacity))
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.55, dampingFraction: 0.82), value: idx)
    }

    private var footer: some View {
        HStack(spacing: 26) {
            Button { mic.toggle() } label: {
                Label(mic.running ? "Singing" : "Sing Along", systemImage: mic.running ? "mic.fill" : "mic")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(mic.running ? .black : .white)
                    .padding(.horizontal, 16).frame(height: 38)
                    .background(Capsule().fill(mic.running ? Color.white : .white.opacity(0.14)))
            }
            .buttonStyle(.plain)
            .help("Score how much you sing along (uses your microphone, nothing is recorded)")

            if mic.running {
                HStack(spacing: 3) {
                    ForEach(0..<12, id: \.self) { i in
                        Capsule()
                            .fill(Double(i) / 12 < mic.level ? (i > 9 ? Color.red : (i > 6 ? .yellow : .green)) : .white.opacity(0.15))
                            .frame(width: 5, height: 10 + CGFloat(i) * 1.6)
                    }
                }
                .animation(.easeOut(duration: 0.08), value: mic.level)
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(mic.score)").font(.system(size: 26, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text("SCORE").font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.5))
                }
                .animation(.spring, value: mic.score)
            } else if mic.denied {
                Text("Allow the microphone in System Settings › Privacy").font(.system(size: 12)).foregroundStyle(.orange)
            }

            ScrubberView(music: music, tint: .white.opacity(0.85), barHeight: 5,
                         font: .system(size: 11, weight: .semibold, design: .rounded),
                         timeColor: .white.opacity(0.5), timesBelow: false)
                .frame(maxWidth: 420)
            TransportControls(music: music, big: false).frame(width: 200)
        }
        .padding(.horizontal, 26).padding(.vertical, 12)
        .glassCapsule()
    }
}

/// "3 · 2 · 1" before the vocals come back in.
private struct Countdown: View {
    let target: Double
    @ObservedObject var music: MusicController
    let size: Double
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { _ in
            let left = target - music.lyricsTime
            HStack(spacing: size * 0.4) {
                ForEach(0..<3, id: \.self) { i in
                    let on = left > Double(2 - i) && left < 3.6
                    Circle()
                        .fill(.white.opacity(on ? 0.95 : 0.18))
                        .frame(width: size * 0.38, height: size * 0.38)
                        .scaleEffect(on ? 1 : 0.7)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: on)
                }
            }
        }
    }
}

import SwiftUI
import AppKit

struct MusicTab: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var music: MusicController

    var body: some View {
        Group {
            if music.track == nil && model.musicPanel == .player {
                EmptyMusic(model: model)
            } else {
                switch model.musicPanel {
                case .player: PlayerView(model: model, music: music)
                case .queue: QueuePanel(model: model, music: music)
                case .devices: DevicesPanel(model: model, music: music)
                case .search: SearchPanel(model: model, music: music)
                }
            }
        }
        .transition(.opacity)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: model.musicPanel)
    }
}

// MARK: Player

private struct PlayerView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var music: MusicController
    @AppStorage(Prefs.showLyricLine) private var showLyricLine = true
    @AppStorage(Prefs.showVisualizer) private var showVisualizer = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                ArtworkView(image: music.artwork, size: 72, radius: 15, accent: music.accent)
                    .islandMatched("art")
                    .shadow(color: music.accent.opacity(0.4), radius: 12, y: 4)
                    .scaleEffect(music.isPlaying ? 1 : 0.9)
                    .rotationEffect(.degrees(music.isPlaying ? 0 : -3))
                    .animation(.spring(response: 0.4, dampingFraction: 0.55), value: music.isPlaying)
                    .id(music.track?.id)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                    .onTapGesture { AppDelegate.shared.openLyrics() }
                    .help("Open full-screen player")

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Image(systemName: music.sourceSymbol)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(music.sourceColor)
                        Text(music.sourceLabel)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(music.track?.title ?? "")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(music.track?.artist ?? "")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                    }
                    .id(music.track?.id)
                    .transition(.push(from: .bottom))
                    if showLyricLine {
                        CurrentLyricLine(music: music, clock: music.clock).padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 10) {
                    LikeButton(music: music, size: 17)
                    if showVisualizer {
                        VisualizerView(isPlaying: music.isPlaying, color: music.accent, bars: 5, height: 16)
                    }
                }
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.75), value: music.track?.id)
            .padding(.horizontal, 22)
            .padding(.top, 6)

            if music.duration > 0 {
                ScrubberView(music: music, tint: .white)
                    .padding(.horizontal, 22)
                    .padding(.top, 8)
            } else {
                Text("Playing in your browser")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(height: 16)
                    .padding(.top, 8)
            }

            HStack(spacing: 22) {
                small(music.shuffle ? "shuffle" : "shuffle", active: music.shuffle, help: "Shuffle") { music.toggleShuffle() }
                Button { music.previous() } label: {
                    Image(systemName: "backward.fill").font(.system(size: 18)).frame(width: 30, height: 26)
                }.buttonStyle(PressableStyle())
                Button { music.playPause() } label: {
                    Image(systemName: music.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 26))
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 40, height: 30)
                }.buttonStyle(PressableStyle())
                Button { music.next() } label: {
                    Image(systemName: "forward.fill").font(.system(size: 18)).frame(width: 30, height: 26)
                }.buttonStyle(PressableStyle())
                small(music.repeatMode == .one ? "repeat.1" : "repeat", active: music.repeatMode != .off, help: "Repeat") {
                    music.cycleRepeat()
                }
            }
            .foregroundStyle(.white)

            HStack(spacing: 4) {
                small("quote.bubble.fill", active: false, dim: music.lyricsState != .loaded, help: "Lyrics (⌥⌘L)") {
                    AppDelegate.shared.openLyrics()
                }
                if music.isSpotify {
                    small("list.bullet", active: false, help: "Up Next & Recently Played") { model.showMusicPanel(.queue) }
                    small("hifispeaker.2.fill", active: false, help: "Play on another device") { model.showMusicPanel(.devices) }
                    small("magnifyingglass", active: false, help: "Search Spotify") { model.showMusicPanel(.search) }
                }
                Spacer(minLength: 8)
                Image(systemName: "speaker.fill").font(.system(size: 9)).foregroundStyle(.white.opacity(0.5))
                VolumeSlider(music: music).frame(width: 110)
                Image(systemName: "speaker.wave.3.fill").font(.system(size: 9)).foregroundStyle(.white.opacity(0.5))
                Spacer(minLength: 8)
                small("link", active: false, help: "Copy song link") { music.copyLink() }
                small(music.source == .spotifyRemote ? music.deviceSymbol : "arrow.up.forward.app.fill", active: false,
                      help: music.source == .spotifyRemote ? "Playing on \(music.deviceName ?? "another device")" : "Open player") {
                    music.openPlayerApp()
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func small(_ icon: String, active: Bool, dim: Bool = false, help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(active ? music.accent : .white.opacity(dim ? 0.3 : 0.65))
                .frame(width: 22, height: 20)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(PressableStyle())
        .help(help)
    }
}

struct LikeButton: View {
    @ObservedObject var music: MusicController
    var size: CGFloat
    @ViewState private var bump = 0

    var body: some View {
        Button {
            music.toggleLike()
            bump += 1
        } label: {
            Image(systemName: music.liked == true ? "heart.fill" : "heart")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(music.liked == true ? Color.pink : .white.opacity(0.6))
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: bump)
        }
        .buttonStyle(.plain)
        .help(music.source == .appleMusic ? "Favorite" : "Save to Liked Songs (⌥⌘K)")
    }
}

struct VolumeSlider: View {
    @ObservedObject var music: MusicController
    var tint: Color = .white
    @ViewState private var drag: Double?

    var body: some View {
        GeometryReader { geo in
            let v = drag ?? Double(music.volume) / 100
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.16))
                Capsule().fill(tint.opacity(0.85)).frame(width: max(4, geo.size.width * v))
            }
            .frame(height: drag == nil ? 4 : 7)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in
                    let nv = min(1, max(0, g.location.x / geo.size.width))
                    drag = nv
                    music.setVolume(Int(nv * 100))
                }
                .onEnded { _ in drag = nil })
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: drag == nil)
        }
        .frame(height: 16)
    }
}

struct CurrentLyricLine: View {
    @ObservedObject var music: MusicController
    @ObservedObject var clock: LyricsClock
    var body: some View {
        let text: String = {
            guard let lyrics = music.lyrics, lyrics.synced, let i = clock.lineIndex else { return "" }
            return lyrics.lines[i].text
        }()
        Text(text.isEmpty ? " " : text)
            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
            .foregroundStyle(music.accent)
            .lineLimit(1)
            .id(text)
            .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal: .move(edge: .top).combined(with: .opacity)))
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: text)
            .clipped()
    }
}

// MARK: Empty

private struct EmptyMusic: View {
    @ObservedObject var model: IslandModel
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "music.note.house.fill")
                .font(.system(size: 30))
                .foregroundStyle(.white.opacity(0.3))
                .symbolEffect(.bounce, options: .repeat(2), value: model.isExpanded)
            VStack(alignment: .leading, spacing: 2) {
                Text("Nothing playing")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Play on your Mac or phone")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            if SpotifyWeb.shared.isConnected {
                pill("Search", "magnifyingglass", .white.opacity(0.15)) { model.showMusicPanel(.search) }
                pill("Recent", "clock.arrow.circlepath", .white.opacity(0.15)) { model.showMusicPanel(.queue) }
            }
            pill("Spotify", "play.circle.fill", Color(red: 0.11, green: 0.73, blue: 0.33)) {
                NSWorkspace.shared.open(URL(string: "spotify:")!)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
    }

    private func pill(_ title: String, _ icon: String, _ color: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .padding(.horizontal, 11).padding(.vertical, 6)
                .foregroundStyle(.white)
                .background(Capsule().fill(color))
        }
        .buttonStyle(PressableStyle(hoverFill: .clear))
    }
}

// MARK: Panels

private struct PanelHeader: View {
    @ObservedObject var model: IslandModel
    let title: String
    var trailing: AnyView? = nil
    var body: some View {
        HStack(spacing: 8) {
            Button { model.showMusicPanel(.player) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(.white.opacity(0.1)))
            }
            .buttonStyle(PressableStyle(hoverFill: .clear))
            Text(title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
            if let trailing { trailing }
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }
}

private struct ConnectPrompt: View {
    let text: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "link.circle.fill").font(.system(size: 26)).foregroundStyle(.green)
            Text(text)
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            Button("Connect Spotify") { AppDelegate.shared.openSettings() }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.11, green: 0.73, blue: 0.33))
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TrackRow: View {
    let track: SpotifyWeb.SimpleTrack
    let index: Int?
    let action: () -> Void
    @ViewState private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let index {
                    Text("\(index)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.35))
                        .frame(width: 16)
                }
                AsyncImage(url: track.artURL) { img in img.resizable() } placeholder: { Color.white.opacity(0.1) }
                    .frame(width: 30, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(track.title).font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white).lineLimit(1)
                    Text(track.artist).font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                }
                Spacer()
                Image(systemName: "play.fill").opacity(hover ? 1 : 0)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.8))
                Text(String(format: "%d:%02d", Int(track.duration) / 60, Int(track.duration) % 60))
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.35))
                    .monospacedDigit()
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(hover ? 0.08 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

private struct QueuePanel: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var music: MusicController
    @ViewState private var showRecent = false

    var body: some View {
        VStack(spacing: 6) {
            PanelHeader(model: model, title: showRecent ? "Recently Played" : "Up Next", trailing: AnyView(
                Picker("", selection: $showRecent) {
                    Text("Up Next").tag(false)
                    Text("Recent").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 150)
            ))
            if !music.webConnected {
                ConnectPrompt(text: "Connect Spotify to see your queue and history")
            } else if music.loadingExtras && music.upNext.isEmpty && music.recent.isEmpty {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let list = showRecent ? music.recent : music.upNext
                if list.isEmpty {
                    Text(showRecent ? "Nothing here yet" : "Your queue is empty")
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(list.enumerated()), id: \.offset) { i, t in
                                TrackRow(track: t, index: showRecent ? nil : i + 1) { music.play(t) }
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                }
            }
        }
    }
}

private struct DevicesPanel: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var music: MusicController

    var body: some View {
        VStack(spacing: 8) {
            PanelHeader(model: model, title: "Play on", trailing: AnyView(
                Button { music.loadDevices() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(PressableStyle())
                    .foregroundStyle(.white.opacity(0.7))
            ))
            if !music.webConnected {
                ConnectPrompt(text: "Connect Spotify to switch between your phone, Mac and speakers")
            } else if music.devices.isEmpty {
                VStack(spacing: 6) {
                    if music.loadingExtras { ProgressView().controlSize(.small) }
                    Text(music.loadingExtras ? "Looking for devices…" : "No devices found. Open Spotify on a device first.")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(music.devices) { d in
                            Button { music.transfer(to: d) } label: {
                                VStack(spacing: 8) {
                                    Image(systemName: Self.symbol(d.type))
                                        .font(.system(size: 28))
                                        .foregroundStyle(d.isActive ? Color.green : .white.opacity(0.85))
                                        .symbolEffect(.variableColor.iterative, isActive: d.isActive && music.isPlaying)
                                    Text(d.name)
                                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.white)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                    Text(d.isActive ? "Playing" : d.type)
                                        .font(.system(size: 10, weight: .medium, design: .rounded))
                                        .foregroundStyle(d.isActive ? .green : .white.opacity(0.4))
                                }
                                .frame(width: 112, height: 130)
                                .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(.white.opacity(d.isActive ? 0.12 : 0.06)))
                                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .strokeBorder(d.isActive ? Color.green.opacity(0.6) : .clear, lineWidth: 1.5))
                            }
                            .buttonStyle(PressableStyle(hoverFill: .clear))
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }

    static func symbol(_ type: String) -> String {
        switch type.lowercased() {
        case "smartphone": return "iphone"
        case "tablet": return "ipad"
        case "computer": return "laptopcomputer"
        case "speaker": return "hifispeaker.fill"
        case "tv": return "tv"
        case "automobile": return "car.fill"
        case "castvideo", "castaudio": return "airplayvideo"
        case "game_console": return "gamecontroller.fill"
        default: return "speaker.wave.2.fill"
        }
    }
}

private struct SearchPanel: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var music: MusicController
    @ViewState private var query = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 6) {
            PanelHeader(model: model, title: "Search")
            if !music.webConnected {
                ConnectPrompt(text: "Connect Spotify to search and play any song")
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.5))
                    TextField("Songs, artists…", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white)
                        .focused($focused)
                        .onSubmit { music.search(query) }
                        .onChange(of: query) { _, q in
                            let snapshot = q
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                if snapshot == query { music.search(q) }
                            }
                        }
                    if music.loadingExtras { ProgressView().controlSize(.mini) }
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().fill(.white.opacity(0.1)))
                .padding(.horizontal, 20)
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 2) {
                        ForEach(music.searchResults) { t in
                            TrackRow(track: t, index: nil) { music.play(t) }
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                AppDelegate.shared.focusIsland()
                focused = true
            }
        }
        .onChange(of: focused) { _, f in model.isEditing = f }
    }
}

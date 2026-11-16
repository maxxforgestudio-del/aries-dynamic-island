import AppKit
import SwiftUI

/// Renders every screen to PNGs offscreen, with made-up demo content (no real songs,
/// lyrics or personal data), for the README and for visual checks.
/// Usage: "Aries Dynamic Island.app"/Contents/MacOS/Aries --snapshot /path/to/dir
enum Snapshotter {
    static func run(app: AppDelegate, out: String) {
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        Task { @MainActor in
            let music = app.music, model = app.model!
            model.notes.persist = false
            music.demoMode = true
            let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main!
            model.updateNotch(for: screen)

            let art = demoArtwork()
            let lyrics = Lyrics(lines: LyricsService.parseLRC(demoLRC), synced: true)
            let track = Track(id: "spotify:track:demo", title: "Paper Moons", artist: "The Quiet Arcade",
                              album: "Night Drive", duration: 214, artworkURL: nil)
            var snap = Snapshot(track: track, isPlaying: true, position: 47, source: .spotifyRemote,
                                deviceName: "iPhone", deviceType: "Smartphone")
            snap.shuffle = true; snap.volume = 64
            music.debugInject(snap, artwork: art, lyrics: lyrics)
            music.debugExtras(upNext: demoQueue(), devices: [
                .init(id: "1", name: "iPhone", type: "Smartphone", isActive: true, volume: 70),
                .init(id: "2", name: "MacBook Air", type: "Computer", isActive: false, volume: 50),
                .init(id: "3", name: "Living Room", type: "Speaker", isActive: false, volume: 40),
            ], liked: true)
            await pause(1.0)

            let canvas = IslandPanelController.canvasSize
            @MainActor func island(_ name: String) {
                render(ZStack(alignment: .top) {
                    LinearGradient(colors: [Color(red: 0.2, green: 0.25, blue: 0.4), Color(red: 0.5, green: 0.35, blue: 0.45)],
                                   startPoint: .top, endPoint: .bottom)
                    Rectangle().fill(.black.opacity(0.25)).frame(height: model.notchSize.height)
                    IslandRootView(model: model, music: music)
                }, size: canvas, to: "\(out)/\(name).png")
            }

            model.collapse(); await pause(3.2)   // let the song announcement finish
            island("01-compact-music")
            let dl = Prefs.bool(Prefs.downloadsActivity)
            UserDefaults.standard.set(true, forKey: Prefs.downloadsActivity)
            model.downloads.debugSet([DownloadItem(id: "x", name: "Night Drive (Stems).zip", bytes: 412_000_000, total: 640_000_000)])
            await pause(0.8)
            island("21-compact-download")
            model.downloads.debugSet([])
            UserDefaults.standard.set(dl, forKey: Prefs.downloadsActivity)
            await pause(0.5)
            model.timer.start(minutes: 25)
            await pause(1.0)
            island("23-bubble-timer")
            model.timer.stop()
            model.handle(url: URL(string: "aries://activity?id=pizza&title=Pizza&subtitle=8%20min&icon=bicycle&color=orange&progress=0.65")!)
            music.debugInject(Snapshot(track: track, isPlaying: false, position: 47, source: .spotify), artwork: art, lyrics: lyrics)
            await pause(25)
            island("24-activity")
            model.live.endAll()
            music.debugInject(snap, artwork: art, lyrics: lyrics)
            await pause(1.0)
            model.expand(to: .music); await pause(1.0)
            island("02-music")
            model.showMusicPanel(.queue); await pause(0.8)
            island("03-music-queue")
            model.showMusicPanel(.devices); await pause(0.8)
            island("04-music-devices")
            model.showMusicPanel(.player)
            model.select(.home); await pause(0.9)
            island("05-home")
            for t in ["Call mom back", "Pick up film at 6", "Finish the Aries README", "Buy oat milk"] { model.notes.add(t) }
            if let n = model.notes.notes.first(where: { $0.text.hasPrefix("Pick") }) { model.notes.toggle(n) }
            if let n = model.notes.notes.first(where: { $0.text.hasPrefix("Finish") }) { model.notes.togglePin(n) }
            model.select(.notes); await pause(0.9)
            island("06-notes")
            model.shelf.clear()
            model.shelf.add([URL(fileURLWithPath: "/System/Applications/Notes.app"),
                             URL(fileURLWithPath: "/System/Applications/Music.app"),
                             URL(fileURLWithPath: "/etc/hosts")])
            model.select(.shelf); await pause(0.9)
            island("07-shelf")
            model.shelf.clear()
            model.timer.start(minutes: 25)
            model.select(.timer); await pause(1.0)
            island("08-timer")
            model.timer.stop()
            model.select(.tools); await pause(1.0)
            island("08b-tools")
            model.collapse(); await pause(0.5)

            model.calls.debugSet(CallInfo(kind: .incoming, title: "Alex Rivera", subtitle: "iPhone", symbol: "phone.fill",
                                          bundleID: nil, startedAt: Date(), isVideo: false))
            await pause(1.2)
            island("09-call-incoming")
            model.calls.debugSet(CallInfo(kind: .active, title: "Alex Rivera", subtitle: "iPhone", symbol: "phone.fill",
                                          bundleID: nil, startedAt: Date().addingTimeInterval(-127), isVideo: false))
            await pause(0.8)
            island("10-call-active")
            model.collapse(); await pause(0.6)
            island("11-compact-call")
            model.calls.debugSet(nil); await pause(0.4)

            model.show(Toast(icon: "music.note", tint: music.accent, title: track.title, detail: track.artist, image: art), for: 10)
            await pause(0.8)
            island("12-song-toast")
            model.confirm("heart.fill", "Added to Liked Songs"); await pause(0.8)
            island("13-liked-toast")
            model.showLevel(icon: "speaker.wave.2.fill", title: "Volume", level: 0.62); await pause(0.8)
            island("14-volume")

            let size = screen.frame.size
            let scroll = LyricsScrollState()
            UserDefaults.standard.set("lyrics", forKey: "playerSide")
            render(FullScreenPlayer(music: music, clock: music.clock, scroll: scroll, close: {}), size: size,
                   to: "\(out)/15-lyrics.png", wait: 2.0)
            UserDefaults.standard.set("vinyl", forKey: Prefs.lyricsStyle)
            render(FullScreenPlayer(music: music, clock: music.clock, scroll: scroll, close: {}), size: size,
                   to: "\(out)/15b-vinyl.png", wait: 2.2)
            UserDefaults.standard.set("karaoke", forKey: Prefs.lyricsStyle)
            render(FullScreenPlayer(music: music, clock: music.clock, scroll: scroll, close: {}), size: size,
                   to: "\(out)/15c-karaoke.png", wait: 2.0)
            UserDefaults.standard.set("lyrics", forKey: Prefs.lyricsStyle)
            let demoTracks: [SpotifyWeb.SimpleTrack] = ["Paper Moons", "Neon Tide", "Static Hearts", "Glass Harbor", "Slow Satellites", "Afterglow Avenue"]
                .enumerated().map { i, n in .init(id: "demo\(i)", uri: "spotify:track:demo\(i)", title: n, artist: "The Quiet Arcade",
                                               artURL: nil, duration: Double(170 + i * 23)) }
            music.debugSpotify(
                artist: .init(id: "demo", uri: "spotify:artist:demo", name: "The Quiet Arcade", imageURL: nil, followers: 1_240_000,
                              genres: ["dream pop", "indie", "synthwave"], top: demoTracks, following: false),
                album: .init(id: "demoalb", uri: "spotify:album:demo", name: "Night Drive Letters", imageURL: nil, year: "2026",
                             label: "Arcade Records", tracks: demoTracks),
                playlists: [])
            UserDefaults.standard.set("artist", forKey: "playerSide")
            render(FullScreenPlayer(music: music, clock: music.clock, scroll: scroll, close: {}), size: size,
                   to: "\(out)/15e-artist.png", wait: 1.2)
            UserDefaults.standard.set("album", forKey: "playerSide")
            render(FullScreenPlayer(music: music, clock: music.clock, scroll: scroll, close: {}), size: size,
                   to: "\(out)/15f-album.png", wait: 1.2)
            UserDefaults.standard.set("lyrics", forKey: "playerSide")
            render(ZStack {
                LinearGradient(colors: [Color(red: 0.2, green: 0.25, blue: 0.5), Color(red: 0.5, green: 0.3, blue: 0.45)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(spacing: 14) {
                    WidgetView(kind: .nowPlaying, model: model)
                    HStack(spacing: 14) { WidgetView(kind: .clock, model: model); WidgetView(kind: .weather, model: model) }
                    HStack(spacing: 14) { WidgetView(kind: .calendar, model: model); WidgetView(kind: .battery, model: model) }
                    WidgetView(kind: .todos, model: model)
                }
            }, size: CGSize(width: 420, height: 780), to: "\(out)/15d-widgets.png", wait: 1.2)
            UserDefaults.standard.set("none", forKey: "playerSide")
            render(FullScreenPlayer(music: music, clock: music.clock, scroll: scroll, close: {}), size: size,
                   to: "\(out)/16-player.png", wait: 1.2)
            UserDefaults.standard.set("lyrics", forKey: "playerSide")

            render(WelcomeFlow(model: model, music: music, finish: {}), size: CGSize(width: 920, height: 620),
                   to: "\(out)/17-welcome.png", wait: 5.5)
            render(WelcomeFlow(model: model, music: music, finish: {}, startAt: 1), size: CGSize(width: 920, height: 620),
                   to: "\(out)/18-welcome-features.png", wait: 1.5)
            render(WelcomeFlow(model: model, music: music, finish: {}, startAt: 4), size: CGSize(width: 920, height: 620),
                   to: "\(out)/19-welcome-done.png", wait: 1.8)
            let pane = UserDefaults.standard.string(forKey: "settingsPane")
            for p in ["music", "updates", "shortcuts"] {
                UserDefaults.standard.set(p, forKey: "settingsPane")
                render(SettingsView(music: music, spotify: SpotifyWeb.shared), size: CGSize(width: 800, height: 600),
                       to: "\(out)/20-settings-\(p).png", wait: 1.0)
            }
            UserDefaults.standard.set(pane, forKey: "settingsPane")
            render(WhatsNewView(done: {}, showClose: true), size: CGSize(width: 720, height: 820), to: "\(out)/22-whats-new.png", wait: 1.5)
            print("done")
            exit(0)
        }
    }

    static let demoLRC = """
    [00:38.00]Paper moons above the parking lot
    [00:42.50]We counted every light the city forgot
    [00:46.80]Your jacket on my shoulders, radio low
    [00:51.20]Singing every word we didn't know
    [00:55.60]
    [01:00.00]And if the night runs out of road
    [01:04.40]We'll fold the stars and take them home
    [01:08.70]Paper moons, paper moons
    [01:13.10]Hanging on a string of afternoons
    [01:17.50]Hold it steady, don't let go
    [01:21.80]Paper moons glow
    """

    static func demoQueue() -> [SpotifyWeb.SimpleTrack] {
        [("Glass Harbor", "Velvet Signal"), ("Slow Satellites", "June & The Static"), ("Afterglow Avenue", "Mira Lane"),
         ("Lemonade Static", "The Quiet Arcade"), ("Northbound", "Coastal Ghosts")].enumerated().map { i, t in
            .init(id: "q\(i)", uri: "", title: t.0, artist: t.1, artURL: nil, duration: Double(180 + i * 17))
        }
    }

    /// Abstract cover art drawn in code.
    static func demoArtwork() -> NSImage {
        let s: CGFloat = 600
        let img = NSImage(size: NSSize(width: s, height: s))
        img.lockFocus()
        NSGradient(colors: [NSColor(srgbRed: 0.98, green: 0.45, blue: 0.55, alpha: 1),
                            NSColor(srgbRed: 0.45, green: 0.3, blue: 0.85, alpha: 1),
                            NSColor(srgbRed: 0.1, green: 0.12, blue: 0.3, alpha: 1)])!
            .draw(in: NSRect(x: 0, y: 0, width: s, height: s), angle: -70)
        NSColor(srgbRed: 1, green: 0.93, blue: 0.8, alpha: 0.95).setFill()
        NSBezierPath(ovalIn: NSRect(x: 330, y: 340, width: 170, height: 170)).fill()
        NSColor(srgbRed: 0.45, green: 0.3, blue: 0.85, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 370, y: 370, width: 150, height: 150)).fill()
        NSColor(white: 0, alpha: 0.35).setFill()
        for i in 0..<9 {
            let w = CGFloat(40 + (i * 37) % 70), h = CGFloat(60 + (i * 53) % 160)
            NSBezierPath(rect: NSRect(x: CGFloat(i) * 68, y: 0, width: w, height: h)).fill()
        }
        img.unlockFocus()
        return img
    }

    @MainActor static func pause(_ s: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000))
    }

    @MainActor static func render<V: View>(_ view: V, size: CGSize, to path: String, wait: Double = 0.6) {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.frame = NSRect(origin: .zero, size: size)
        let win = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: size.width, height: size.height),
                           styleMask: [.borderless], backing: .buffered, defer: false)
        win.contentView = host
        win.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(wait))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        win.orderOut(nil)
    }
}

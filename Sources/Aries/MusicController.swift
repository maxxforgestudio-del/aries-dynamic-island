import AppKit
import SwiftUI

/// Publishes the current synced-lyric line separately so only lyric views redraw on each tick.
final class LyricsClock: ObservableObject {
    @Published var lineIndex: Int?
}

enum LyricsState: Equatable { case idle, loading, loaded, unavailable }

/// Merges Spotify (this Mac), Apple Music (this Mac) and Spotify Connect (your phone)
/// into a single "now playing" state.
final class MusicController: ObservableObject {
    @Published private(set) var track: Track?
    @Published private(set) var isPlaying = false
    @Published private(set) var source: MusicSource = .spotify
    @Published private(set) var deviceName: String?
    @Published private(set) var deviceType: String?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var backdrop: NSImage?
    @Published private(set) var accent: Color = .white
    @Published private(set) var lyrics: Lyrics?
    @Published private(set) var lyricsState: LyricsState = .idle
    @Published private(set) var shuffle = false
    @Published private(set) var repeatMode: RepeatMode = .off
    @Published private(set) var volume: Int = 50
    @Published private(set) var liked: Bool?
    @Published private(set) var palette: [Color] = []

    // Spotify extras (filled on demand)
    @Published private(set) var upNext: [SpotifyWeb.SimpleTrack] = []
    @Published private(set) var recent: [SpotifyWeb.SimpleTrack] = []
    @Published private(set) var searchResults: [SpotifyWeb.SimpleTrack] = []
    @Published private(set) var devices: [SpotifyWeb.Device] = []
    @Published private(set) var loadingExtras = false

    /// Called with a short confirmation message ("Added to Liked Songs") for the island to show.
    var onConfirm: ((String, String) -> Void)?
    private var volumeHoldUntil = Date.distantPast
    private var likeHoldUntil = Date.distantPast

    let clock = LyricsClock()

    private var anchorPosition: Double = 0
    private var anchorDate = Date()
    private var localSpotify: Snapshot?
    private var localMusic: Snapshot?
    private var remote: Snapshot?
    private var remoteInFlight = false
    private var timers: [Timer] = []
    private var ignoreUntil = Date.distantPast

    var duration: Double { track?.duration ?? 0 }

    var position: Double {
        let p = isPlaying ? anchorPosition + Date().timeIntervalSince(anchorDate) : anchorPosition
        return min(max(0, p), max(duration, 0))
    }

    // MARK: Lifecycle

    func start() {
        timers.append(Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.pollLocal() })
        timers.append(Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in self?.pollRemote() })
        timers.append(Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in self?.tickLyrics() })
        timers.forEach { RunLoop.main.add($0, forMode: .common) }

        let dnc = DistributedNotificationCenter.default()
        for name in ["com.spotify.client.PlaybackStateChanged", "com.apple.Music.playerInfo"] {
            dnc.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                self?.pollLocal()
            }
        }
        pollLocal()
        pollRemote()
    }

    /// Used by the offscreen snapshot renderer (`Aries --snapshot <dir>`).
    func debugInject(_ s: Snapshot, artwork: NSImage?, lyrics: Lyrics?) {
        track = s.track; isPlaying = s.isPlaying; source = s.source
        deviceName = s.deviceName; deviceType = s.deviceType
        anchorPosition = s.position; anchorDate = Date()
        self.artwork = artwork
        backdrop = artwork?.blurredBackdrop()
        accent = artwork.map { Color(nsColor: $0.accentColor()) } ?? .white
        palette = artwork?.palette() ?? []
        shuffle = s.shuffle ?? false
        repeatMode = s.repeatMode ?? .off
        volume = s.volume ?? 60
        liked = s.favorited
        self.lyrics = lyrics
        lyricsState = lyrics == nil ? .unavailable : .loaded
        tickLyrics()
    }

    func debugExtras(upNext: [SpotifyWeb.SimpleTrack], devices: [SpotifyWeb.Device], liked: Bool) {
        self.upNext = upNext; self.devices = devices; self.liked = liked
    }

    // MARK: Polling

    func pollLocal() {
        LocalPlayers.queue.async { [weak self] in
            let s = LocalPlayers.spotify()
            let m = LocalPlayers.music()
            DispatchQueue.main.async {
                guard let self else { return }
                self.localSpotify = s
                self.localMusic = m
                self.reconcile()
            }
        }
    }

    func pollRemote() {
        guard Prefs.bool(Prefs.usePhoneSpotify), SpotifyWeb.shared.isConnected else {
            if remote != nil { remote = nil; reconcile() }
            return
        }
        // Spotify on this Mac already tells us everything while it's playing.
        if localSpotify?.isPlaying == true { remote = nil; return }
        guard !remoteInFlight else { return }
        remoteInFlight = true
        Task {
            let r = await SpotifyWeb.shared.fetchPlayback()
            await MainActor.run {
                self.remoteInFlight = false
                self.remote = r
                self.reconcile()
            }
        }
    }

    private func reconcile() {
        guard Date() >= ignoreUntil else { return }
        var remoteSnap = remote
        if var r = remoteSnap {
            if r.isPlaying { r.position += Date().timeIntervalSince(r.fetchedAt) }
            // Same song as the Spotify app on this Mac → it's this Mac, not the phone.
            if let l = localSpotify, l.track.id == r.track.id, r.deviceType == "Computer" { remoteSnap = nil }
            else { remoteSnap = r }
        }
        let order: [Snapshot?] = Prefs.string(Prefs.preferredSource) == "music"
            ? [localMusic, localSpotify, remoteSnap]
            : (Prefs.string(Prefs.preferredSource) == "spotify"
               ? [localSpotify, remoteSnap, localMusic]
               : [localSpotify, remoteSnap, localMusic])
        let candidates = order.compactMap { $0 }
        let chosen = candidates.first(where: { $0.isPlaying })
            ?? candidates.first(where: { $0.source == source && $0.track.id == track?.id })
            ?? candidates.first
        apply(chosen)
    }

    private func apply(_ s: Snapshot?) {
        guard let s else {
            if track != nil {
                track = nil; isPlaying = false; artwork = nil; backdrop = nil
                lyrics = nil; lyricsState = .idle; clock.lineIndex = nil
                NowPlayingBridge.shared.update(self)
            }
            return
        }
        let changed = s.track.id != track?.id
        if changed {
            track = s.track
            anchorPosition = s.position; anchorDate = Date()
            liked = nil
            loadArtwork(for: s)
            loadLyrics(for: s.track)
            refreshLiked(for: s.track)
        } else if track != s.track {
            track = s.track
        }
        if source != s.source { source = s.source }
        if deviceName != s.deviceName { deviceName = s.deviceName }
        if deviceType != s.deviceType { deviceType = s.deviceType }

        let drift = abs(position - s.position)
        if isPlaying != s.isPlaying || drift > 1.2 {
            anchorPosition = s.position; anchorDate = Date()
        }
        if isPlaying != s.isPlaying { isPlaying = s.isPlaying }
        if let v = s.shuffle, v != shuffle { shuffle = v }
        if let r = s.repeatMode, r != repeatMode { repeatMode = r }
        if let v = s.volume, v != volume, Date() > volumeHoldUntil { volume = v }
        if s.source == .appleMusic, let f = s.favorited, f != liked, Date() > likeHoldUntil { liked = f }
        NowPlayingBridge.shared.update(self)
    }

    // MARK: Artwork + lyrics

    private func loadArtwork(for s: Snapshot) {
        let id = s.track.id
        artwork = nil
        backdrop = nil
        Task {
            var img: NSImage?
            if let url = s.track.artworkURL { img = await ArtworkLoader.load(url: url) }
            if img == nil, s.source == .appleMusic {
                let data: Data? = await withCheckedContinuation { cont in
                    LocalPlayers.queue.async { cont.resume(returning: LocalPlayers.musicArtwork()) }
                }
                img = data.flatMap(NSImage.init(data:))
            }
            if img == nil { img = await ArtworkLoader.lookup(title: s.track.title, artist: s.track.artist) }
            let finalImage = img
            let accent = finalImage?.accentColor()
            let backdrop = finalImage?.blurredBackdrop()
            let palette = finalImage?.palette() ?? []
            await MainActor.run {
                guard self.track?.id == id else { return }
                self.artwork = finalImage
                self.palette = palette
                NowPlayingBridge.shared.update(self)
                self.backdrop = backdrop
                self.accent = (Prefs.bool(Prefs.artworkAccent) ? accent.map(Color.init(nsColor:)) : nil) ?? .white
            }
        }
    }

    private func loadLyrics(for t: Track) {
        lyrics = nil
        lyricsState = .loading
        clock.lineIndex = nil
        let id = t.id
        Task {
            let result = await LyricsService.fetch(title: t.title, artist: t.artist, album: t.album, duration: t.duration)
            await MainActor.run {
                guard self.track?.id == id else { return }
                self.lyrics = result
                self.lyricsState = (result?.lines.isEmpty == false) ? .loaded : .unavailable
            }
        }
    }

    private func tickLyrics() {
        guard let l = lyrics, l.synced else {
            if clock.lineIndex != nil { clock.lineIndex = nil }
            return
        }
        let idx = l.index(at: position + 0.25)
        if clock.lineIndex != idx { clock.lineIndex = idx }
    }

    // MARK: Controls

    private func settle(after: Double = 0.6) {
        ignoreUntil = Date().addingTimeInterval(after)
        DispatchQueue.main.asyncAfter(deadline: .now() + after + 0.05) { [weak self] in
            self?.pollLocal()
            self?.remoteInFlight = false
            self?.pollRemote()
        }
    }

    func playPause() {
        switch source {
        case .spotify, .appleMusic: LocalPlayers.send(source, "playpause")
        case .spotifyRemote: Task { await SpotifyWeb.shared.setPlaying(!isPlaying) }
        }
        anchorPosition = position; anchorDate = Date()
        isPlaying.toggle()
        settle(after: source == .spotifyRemote ? 1.2 : 0.5)
    }

    func next() {
        switch source {
        case .spotify, .appleMusic: LocalPlayers.send(source, "next track")
        case .spotifyRemote: Task { await SpotifyWeb.shared.skip(forward: true) }
        }
        settle(after: 0.4)
    }

    func previous() {
        switch source {
        case .spotify, .appleMusic: LocalPlayers.send(source, "previous track")
        case .spotifyRemote: Task { await SpotifyWeb.shared.skip(forward: false) }
        }
        settle(after: 0.4)
    }

    func seek(to t: Double) {
        let target = min(max(0, t), duration)
        switch source {
        case .spotify, .appleMusic:
            LocalPlayers.send(source, "set player position to \(String(format: "%.2f", target))")
        case .spotifyRemote:
            Task { await SpotifyWeb.shared.seek(to: target) }
        }
        anchorPosition = target; anchorDate = Date()
        objectWillChange.send()
        tickLyrics()
        settle(after: source == .spotifyRemote ? 1.5 : 0.6)
    }

    func openPlayerApp() {
        switch source {
        case .spotify, .spotifyRemote:
            NSWorkspace.shared.open(URL(string: "spotify:")!)
        case .appleMusic:
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: LocalPlayers.musicID) {
                NSWorkspace.shared.openApplication(at: url, configuration: .init())
            }
        }
    }

    // MARK: Music extras

    var isSpotify: Bool { source != .appleMusic }
    var webConnected: Bool { SpotifyWeb.shared.isConnected || demoMode }
    var demoMode = false

    private func refreshLiked(for t: Track) {
        guard let sid = t.spotifyID, SpotifyWeb.shared.isConnected else { return }
        Task {
            let v = await SpotifyWeb.shared.isSaved(sid)
            await MainActor.run { if self.track?.id == t.id, Date() > self.likeHoldUntil { self.liked = v } }
        }
    }

    func toggleLike() {
        guard let t = track else { return }
        let target = !(liked ?? false)
        likeHoldUntil = Date().addingTimeInterval(4)
        liked = target
        if source == .appleMusic {
            LocalPlayers.setFavorited(target)
            onConfirm?(target ? "heart.fill" : "heart.slash", target ? "Added to Favorites" : "Removed from Favorites")
            return
        }
        guard let sid = t.spotifyID else { return }
        guard SpotifyWeb.shared.isConnected else {
            liked = nil
            onConfirm?("exclamationmark.circle", "Connect Spotify in Settings")
            return
        }
        Task {
            let ok = await SpotifyWeb.shared.setSaved(sid, target)
            await MainActor.run {
                if ok {
                    self.onConfirm?(target ? "heart.fill" : "heart.slash", target ? "Added to Liked Songs" : "Removed from Liked Songs")
                } else {
                    self.liked = !target
                    self.onConfirm?("exclamationmark.circle", "Couldn't update Liked Songs")
                }
            }
        }
    }

    func toggleShuffle() {
        shuffle.toggle()
        switch source {
        case .spotify, .appleMusic: LocalPlayers.setShuffle(source, shuffle)
        case .spotifyRemote: let v = shuffle; Task { await SpotifyWeb.shared.setShuffle(v) }
        }
        settle(after: 1.0)
    }

    func cycleRepeat() {
        // Spotify's desktop scripting only knows on/off; the Web API and Music know "one" too.
        let canOne = source != .spotify
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = canOne ? .one : .off
        case .one: repeatMode = .off
        }
        let m = repeatMode
        switch source {
        case .spotify, .appleMusic: LocalPlayers.setRepeat(source, m)
        case .spotifyRemote: Task { await SpotifyWeb.shared.setRepeat(m) }
        }
        settle(after: 1.0)
    }

    private var volumeWork: DispatchWorkItem?
    func setVolume(_ v: Int) {
        volume = v
        volumeHoldUntil = Date().addingTimeInterval(2)
        volumeWork?.cancel()
        let src = source
        let w = DispatchWorkItem {
            switch src {
            case .spotify, .appleMusic: LocalPlayers.setVolume(src, v)
            case .spotifyRemote: Task { await SpotifyWeb.shared.setVolume(v) }
            }
        }
        volumeWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: w)
    }

    func copyLink() {
        guard let t = track else { return }
        let text = t.shareURL?.absoluteString ?? "\(t.title) — \(t.artist)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        onConfirm?("link", t.shareURL != nil ? "Song link copied" : "Song name copied")
    }

    func loadQueue() {
        guard SpotifyWeb.shared.isConnected else { return }
        loadingExtras = true
        Task {
            let q = await SpotifyWeb.shared.queue()
            let r = await SpotifyWeb.shared.recentlyPlayed()
            await MainActor.run { self.upNext = q; self.recent = r; self.loadingExtras = false }
        }
    }

    func loadDevices() {
        guard SpotifyWeb.shared.isConnected else { return }
        loadingExtras = true
        Task {
            let d = await SpotifyWeb.shared.devices()
            await MainActor.run { self.devices = d; self.loadingExtras = false }
        }
    }

    func transfer(to d: SpotifyWeb.Device) {
        Task {
            let ok = await SpotifyWeb.shared.transfer(to: d.id)
            await MainActor.run {
                self.onConfirm?(ok ? "hifispeaker.and.homepod.fill" : "exclamationmark.circle",
                                ok ? "Playing on \(d.name)" : "Spotify Premium is needed for this")
                self.loadDevices()
                self.settle(after: 1.5)
            }
        }
    }

    func search(_ q: String) {
        let query = q.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty, SpotifyWeb.shared.isConnected else { searchResults = []; return }
        loadingExtras = true
        Task {
            let r = await SpotifyWeb.shared.search(query)
            await MainActor.run { self.searchResults = r; self.loadingExtras = false }
        }
    }

    func play(_ t: SpotifyWeb.SimpleTrack) {
        let localSpotify = LocalPlayers.isRunning(LocalPlayers.spotifyID)
        if source == .spotify || (localSpotify && source != .spotifyRemote) {
            LocalPlayers.playSpotifyURI(t.uri)
            onConfirm?("play.fill", "Playing \(t.title)")
            settle(after: 1.0)
            return
        }
        Task {
            let ok = await SpotifyWeb.shared.play(uri: t.uri)
            await MainActor.run {
                if ok { self.onConfirm?("play.fill", "Playing \(t.title)") }
                else { LocalPlayers.playSpotifyURI(t.uri); self.onConfirm?("play.fill", "Opening in Spotify") }
                self.settle(after: 1.5)
            }
        }
    }

    // MARK: Presentation helpers

    var sourceLabel: String {
        switch source {
        case .spotify: return "Spotify"
        case .appleMusic: return "Music"
        case .spotifyRemote: return "Spotify · \(deviceName ?? "Phone")"
        }
    }

    var sourceSymbol: String {
        switch source {
        case .spotify: return "circle.fill"
        case .appleMusic: return "music.note"
        case .spotifyRemote: return deviceSymbol
        }
    }

    var sourceColor: Color {
        source == .appleMusic ? Color(red: 0.98, green: 0.24, blue: 0.33) : Color(red: 0.11, green: 0.84, blue: 0.38)
    }

    var deviceSymbol: String {
        switch deviceType?.lowercased() {
        case "smartphone": return "iphone"
        case "tablet": return "ipad"
        case "speaker": return "hifispeaker.fill"
        case "tv": return "tv"
        case "computer": return "laptopcomputer"
        default: return "dot.radiowaves.left.and.right"
        }
    }
}

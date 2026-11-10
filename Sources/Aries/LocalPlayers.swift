import AppKit

enum MusicSource: String {
    case spotify          // Spotify app on this Mac
    case appleMusic       // Music app on this Mac
    case spotifyRemote    // Spotify on another device (your iPhone) via Spotify Connect
}

enum RepeatMode: String { case off, all, one }

struct Track: Equatable {
    var id: String
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var artworkURL: URL?

    /// Spotify track id (without the "spotify:track:" prefix), if this is a Spotify track.
    var spotifyID: String? {
        id.hasPrefix("spotify:track:") ? String(id.dropFirst("spotify:track:".count)) : nil
    }
    var shareURL: URL? {
        spotifyID.flatMap { URL(string: "https://open.spotify.com/track/\($0)") }
    }
}

struct Snapshot {
    var track: Track
    var isPlaying: Bool
    var position: Double
    var source: MusicSource
    var deviceName: String? = nil
    var deviceType: String? = nil
    var fetchedAt = Date()
    var shuffle: Bool? = nil
    var repeatMode: RepeatMode? = nil
    var volume: Int? = nil
    var favorited: Bool? = nil
}

/// Talks to Spotify and Music on this Mac through AppleScript.
/// Everything runs on one serial queue (NSAppleScript is not thread-safe).
enum LocalPlayers {
    static let queue = DispatchQueue(label: "aries.localplayers", qos: .userInitiated)
    static let spotifyID = "com.spotify.client"
    static let musicID = "com.apple.Music"

    private static var cache: [String: NSAppleScript] = [:]

    static func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    @discardableResult
    static func run(_ source: String) -> NSAppleEventDescriptor? {
        let script: NSAppleScript
        if let s = cache[source] {
            script = s
        } else {
            guard let s = NSAppleScript(source: source) else { return nil }
            var err: NSDictionary?
            s.compileAndReturnError(&err)
            if err != nil { return nil }
            cache[source] = s
            script = s
        }
        var err: NSDictionary?
        let result = script.executeAndReturnError(&err)
        return err == nil ? result : nil
    }

    private static func num(_ d: NSAppleEventDescriptor?) -> Double {
        guard let d else { return 0 }
        if let s = d.stringValue, let v = Double(s.replacingOccurrences(of: ",", with: ".")) { return v }
        return d.doubleValue
    }

    private static func bool(_ d: NSAppleEventDescriptor?) -> Bool? {
        guard let s = d?.stringValue?.lowercased() else { return nil }
        return s == "true" || s == "yes" || s == "1"
    }

    // MARK: Spotify

    private static let spotifyScript = """
    tell application "Spotify"
        if player state is stopped then return {"stopped"}
        set t to current track
        if player state is playing then
            set s to "playing"
        else
            set s to "paused"
        end if
        return {s, name of t, artist of t, album of t, duration of t, player position, artwork url of t, id of t, shuffling as string, repeating as string, sound volume}
    end tell
    """

    static func spotify() -> Snapshot? {
        guard isRunning(spotifyID), let d = run(spotifyScript), d.numberOfItems >= 8 else { return nil }
        let title = d.atIndex(2)?.stringValue ?? ""
        guard !title.isEmpty else { return nil }
        let artist = d.atIndex(3)?.stringValue ?? ""
        let track = Track(
            id: d.atIndex(8)?.stringValue ?? "\(title)|\(artist)",
            title: title, artist: artist,
            album: d.atIndex(4)?.stringValue ?? "",
            duration: num(d.atIndex(5)) / 1000.0,
            artworkURL: d.atIndex(7)?.stringValue.flatMap(URL.init(string:)))
        var snap = Snapshot(track: track, isPlaying: d.atIndex(1)?.stringValue == "playing",
                            position: num(d.atIndex(6)), source: .spotify)
        if d.numberOfItems >= 11 {
            snap.shuffle = bool(d.atIndex(9))
            snap.repeatMode = bool(d.atIndex(10)) == true ? .all : .off
            snap.volume = Int(num(d.atIndex(11)))
        }
        return snap
    }

    // MARK: Apple Music

    private static let musicScript = """
    tell application "Music"
        try
            if player state is stopped then return {"stopped"}
            set t to current track
            if player state is playing then
                set s to "playing"
            else
                set s to "paused"
            end if
            set p to 0
            try
                set p to player position
            end try
            set fav to "false"
            try
                set fav to (favorited of t) as string
            end try
            return {s, name of t, artist of t, album of t, duration of t, p, persistent ID of t, shuffle enabled as string, song repeat as string, sound volume, fav}
        on error
            return {"stopped"}
        end try
    end tell
    """

    private static let musicArtScript = """
    tell application "Music"
        try
            return raw data of artwork 1 of current track
        on error
            return ""
        end try
    end tell
    """

    static func music() -> Snapshot? {
        guard isRunning(musicID), let d = run(musicScript), d.numberOfItems >= 7 else { return nil }
        let title = d.atIndex(2)?.stringValue ?? ""
        guard !title.isEmpty else { return nil }
        let artist = d.atIndex(3)?.stringValue ?? ""
        let track = Track(
            id: "am:" + (d.atIndex(7)?.stringValue ?? "\(title)|\(artist)"),
            title: title, artist: artist,
            album: d.atIndex(4)?.stringValue ?? "",
            duration: num(d.atIndex(5)), artworkURL: nil)
        var snap = Snapshot(track: track, isPlaying: d.atIndex(1)?.stringValue == "playing",
                            position: num(d.atIndex(6)), source: .appleMusic)
        if d.numberOfItems >= 11 {
            snap.shuffle = bool(d.atIndex(8))
            switch d.atIndex(9)?.stringValue?.lowercased() {
            case "one": snap.repeatMode = .one
            case "all": snap.repeatMode = .all
            default: snap.repeatMode = .off
            }
            snap.volume = Int(num(d.atIndex(10)))
            snap.favorited = bool(d.atIndex(11))
        }
        return snap
    }

    static func musicArtwork() -> Data? {
        guard isRunning(musicID), let d = run(musicArtScript) else { return nil }
        let data = d.data
        return data.count > 100 ? data : nil
    }

    // MARK: Commands

    static func send(_ source: MusicSource, _ command: String) {
        let (app, bid) = source == .appleMusic ? ("Music", musicID) : ("Spotify", spotifyID)
        queue.async {
            guard isRunning(bid) else { return }
            run("tell application \"\(app)\" to \(command)")
        }
    }

    static func setShuffle(_ source: MusicSource, _ on: Bool) {
        send(source, source == .appleMusic ? "set shuffle enabled to \(on)" : "set shuffling to \(on)")
    }

    static func setRepeat(_ source: MusicSource, _ mode: RepeatMode) {
        if source == .appleMusic {
            send(source, "set song repeat to \(mode.rawValue)")
        } else {
            send(source, "set repeating to \(mode != .off)")
        }
    }

    static func setVolume(_ source: MusicSource, _ v: Int) {
        send(source, "set sound volume to \(max(0, min(100, v)))")
    }

    static func setFavorited(_ on: Bool) {
        send(.appleMusic, "set favorited of current track to \(on)")
    }

    /// Plays a Spotify URI in the Spotify app on this Mac (no Premium/API needed).
    static func playSpotifyURI(_ uri: String) {
        queue.async {
            if !isRunning(spotifyID) {
                NSWorkspace.shared.open(URL(string: "spotify:")!)
                Thread.sleep(forTimeInterval: 2.5)
            }
            run("tell application \"Spotify\" to play track \"\(uri)\"")
        }
    }
}

import AppKit

/// Web music players (beta): reads what's playing from browser tabs — YouTube Music, YouTube,
/// SoundCloud, Tidal, Deezer, Amazon Music, Pandora and Spotify's web player — using the
/// browsers' standard scripting (macOS asks once per browser). Read-only; play/pause/skip
/// use the Mac's media keys.
enum WebPlayers {
    struct Service { let host: String; let name: String; let suffixes: [String] }

    static let services: [Service] = [
        .init(host: "music.youtube.com", name: "YouTube Music", suffixes: [" - YouTube Music"]),
        .init(host: "youtube.com/watch", name: "YouTube", suffixes: [" - YouTube"]),
        .init(host: "soundcloud.com", name: "SoundCloud", suffixes: [" | Listen online for free on SoundCloud", " | SoundCloud"]),
        .init(host: "listen.tidal.com", name: "TIDAL", suffixes: [" | TIDAL", " on TIDAL"]),
        .init(host: "deezer.com", name: "Deezer", suffixes: [" | Deezer", " - Deezer"]),
        .init(host: "music.amazon", name: "Amazon Music", suffixes: [" | Amazon Music", " - Amazon Music"]),
        .init(host: "pandora.com", name: "Pandora", suffixes: [" - Pandora", " | Pandora"]),
        .init(host: "open.spotify.com", name: "Spotify Web", suffixes: [" | Spotify", " - Spotify"]),
    ]

    static let browsers: [(id: String, name: String, safari: Bool)] = [
        ("com.apple.Safari", "Safari", true),
        ("com.google.Chrome", "Google Chrome", false),
        ("company.thebrowser.Browser", "Arc", false),
        ("com.microsoft.edgemac", "Microsoft Edge", false),
        ("com.brave.Browser", "Brave Browser", false),
    ]

    /// Runs on LocalPlayers.queue.
    static func snapshot() -> Snapshot? {
        guard Prefs.bool(Prefs.webPlayers) else { return nil }
        for b in browsers where LocalPlayers.isRunning(b.id) {
            let script = b.safari
                ? "tell application \"Safari\" to get {name, URL} of every tab of every window"
                : "tell application \"\(b.name)\" to get {title, URL} of every tab of every window"
            guard let d = LocalPlayers.run(script), d.numberOfItems == 2,
                  let titlesByWin = d.atIndex(1), let urlsByWin = d.atIndex(2) else { continue }
            for w in 0..<titlesByWin.numberOfItems {
                guard let titles = titlesByWin.atIndex(w + 1), let urls = urlsByWin.atIndex(w + 1) else { continue }
                for i in 0..<titles.numberOfItems {
                    let url = urls.atIndex(i + 1)?.stringValue ?? ""
                    let title = titles.atIndex(i + 1)?.stringValue ?? ""
                    guard let svc = services.first(where: { url.contains($0.host) }),
                          let parsed = parse(title, svc) else { continue }
                    let track = Track(id: "web:" + parsed.title + "|" + parsed.artist, title: parsed.title,
                                      artist: parsed.artist, album: "", duration: 0, artworkURL: nil)
                    // Tab titles start with "▶" or a count while some sites play; we can't know for sure,
                    // so a matching music tab counts as playing.
                    return Snapshot(track: track, isPlaying: true, position: 0, source: .web,
                                    deviceName: "\(svc.name) · \(b.name)", deviceType: "web")
                }
            }
        }
        return nil
    }

    static func parse(_ raw: String, _ svc: Service) -> (title: String, artist: String)? {
        var t = raw.replacingOccurrences(of: #"^\(\d+\)\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "▶ ", with: "").trimmingCharacters(in: .whitespaces)
        for s in svc.suffixes where t.hasSuffix(s) { t = String(t.dropLast(s.count)) }
        // Home pages, searches and library views aren't songs.
        let generic = ["YouTube Music", "YouTube", "SoundCloud", "TIDAL", "Deezer", "Amazon Music", "Pandora", "Spotify",
                       "Spotify - Web Player", "Home", "Library", "Search"]
        if t.isEmpty || generic.contains(where: { t.caseInsensitiveCompare($0) == .orderedSame }) { return nil }
        if t.hasPrefix("Stream "), let r = t.range(of: " by ") {          // SoundCloud
            return (String(t[t.index(t.startIndex, offsetBy: 7)..<r.lowerBound]), String(t[r.upperBound...]))
        }
        for sep in [" • ", " – ", " - ", " · "] {
            let parts = t.components(separatedBy: sep)
            if parts.count >= 2 { return (parts[0].trimmingCharacters(in: .whitespaces), parts[1].trimmingCharacters(in: .whitespaces)) }
        }
        return (t, svc.name)
    }

    /// Sends a hardware media key (play/pause, next, previous) — routed by macOS to the browser.
    /// Needs Accessibility.
    static func mediaKey(_ key: Int32) {
        func post(_ down: Bool) {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
            let data1 = Int((key << 16) | ((down ? 0xA : 0xB) << 8))
            let e = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags, timestamp: 0,
                                       windowNumber: 0, context: nil, subtype: 8, data1: data1, data2: -1)
            e?.cgEvent?.post(tap: .cghidEventTap)
        }
        post(true); post(false)
    }
    static let keyPlay: Int32 = 16, keyNext: Int32 = 17, keyPrevious: Int32 = 18
}

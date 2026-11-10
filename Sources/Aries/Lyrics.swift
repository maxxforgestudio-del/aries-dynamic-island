import Foundation

struct LyricLine: Identifiable, Equatable {
    let id: Int
    let time: Double
    let text: String
    var isInterlude: Bool { text.trimmingCharacters(in: .whitespaces).isEmpty }
}

struct Lyrics: Equatable {
    let lines: [LyricLine]
    let synced: Bool

    /// Index of the line being sung at `t` seconds.
    func index(at t: Double) -> Int? {
        guard synced, let first = lines.first, t >= first.time else { return nil }
        var lo = 0, hi = lines.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if lines[mid].time <= t { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }
}

/// Synced lyrics from LRCLIB (free, open lyrics database).
enum LyricsService {
    private static var cache: [String: Lyrics?] = [:]
    private static let lock = NSLock()

    static func fetch(title: String, artist: String, album: String, duration: Double) async -> Lyrics? {
        let key = "\(artist)|\(title)".lowercased()
        let cached = lock.withLock { cache[key] }
        if let cached { return cached }

        let primaryArtist = artist.components(separatedBy: ", ").first ?? artist
        var result = await get(title: title, artist: primaryArtist, album: album, duration: duration)
        let clean = cleanTitle(title)
        if result == nil, clean != title {
            result = await get(title: clean, artist: primaryArtist, album: album, duration: duration)
        }
        if result == nil {
            result = await search(title: clean, artist: primaryArtist, duration: duration)
        }

        lock.withLock { cache[key] = .some(result) }
        return result
    }

    /// "Song - Remastered 2011" / "Song (feat. X)" → "Song"
    static func cleanTitle(_ t: String) -> String {
        var s = t
        for pattern in [#"\s*[\(\[](feat|ft|with)\.?[^\)\]]*[\)\]]"#,
                        #"\s+-\s+.*(remaster|version|edit|mix|live|mono|stereo|from).*$"#] {
            s = s.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        return s.trimmingCharacters(in: .whitespaces)
    }

    private static func request(_ path: String, _ items: [URLQueryItem]) -> URLRequest {
        var c = URLComponents(string: "https://lrclib.net/api/" + path)!
        c.queryItems = items
        var r = URLRequest(url: c.url!)
        r.setValue("AriesDynamicIsland/1.0 (macOS notch app)", forHTTPHeaderField: "User-Agent")
        r.timeoutInterval = 10
        return r
    }

    private static func get(title: String, artist: String, album: String, duration: Double) async -> Lyrics? {
        var items: [URLQueryItem] = [.init(name: "track_name", value: title), .init(name: "artist_name", value: artist)]
        if !album.isEmpty { items.append(.init(name: "album_name", value: album)) }
        if duration > 0 { items.append(.init(name: "duration", value: String(Int(duration.rounded())))) }
        guard let (data, resp) = try? await URLSession.shared.data(for: request("get", items)),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return parse(obj)
    }

    private static func search(title: String, artist: String, duration: Double) async -> Lyrics? {
        let items: [URLQueryItem] = [.init(name: "track_name", value: title), .init(name: "artist_name", value: artist)]
        guard let (data, _) = try? await URLSession.shared.data(for: request("search", items)),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]], !arr.isEmpty else { return nil }
        let ranked = arr.sorted { a, b in
            let sa = (a["syncedLyrics"] as? String) != nil ? 0 : 1
            let sb = (b["syncedLyrics"] as? String) != nil ? 0 : 1
            if sa != sb { return sa < sb }
            let da = abs(((a["duration"] as? Double) ?? 0) - duration)
            let db = abs(((b["duration"] as? Double) ?? 0) - duration)
            return da < db
        }
        for obj in ranked.prefix(3) {
            if let l = parse(obj) { return l }
        }
        return nil
    }

    private static func parse(_ obj: [String: Any]) -> Lyrics? {
        if let synced = obj["syncedLyrics"] as? String, !synced.isEmpty {
            let lines = parseLRC(synced)
            if !lines.isEmpty { return Lyrics(lines: lines, synced: true) }
        }
        if let plain = obj["plainLyrics"] as? String, !plain.isEmpty {
            let lines = plain.components(separatedBy: .newlines).enumerated()
                .map { LyricLine(id: $0.offset, time: 0, text: $0.element) }
            return Lyrics(lines: lines, synced: false)
        }
        return nil
    }

    static func parseLRC(_ s: String) -> [LyricLine] {
        let tag = try! NSRegularExpression(pattern: #"\[(\d+):(\d+(?:[\.:]\d+)?)\]"#)
        var out: [(Double, String)] = []
        for raw in s.components(separatedBy: .newlines) {
            let ns = raw as NSString
            let matches = tag.matches(in: raw, range: NSRange(location: 0, length: ns.length))
            guard let last = matches.last else { continue }
            let text = ns.substring(from: last.range.location + last.range.length).trimmingCharacters(in: .whitespaces)
            for m in matches {
                let min = Double(ns.substring(with: m.range(at: 1))) ?? 0
                let sec = Double(ns.substring(with: m.range(at: 2)).replacingOccurrences(of: ":", with: ".")) ?? 0
                out.append((min * 60 + sec, text))
            }
        }
        out.sort { $0.0 < $1.0 }
        // Collapse consecutive empty lines.
        var lines: [LyricLine] = []
        for (t, text) in out {
            if text.isEmpty, lines.last?.isInterlude == true { continue }
            lines.append(LyricLine(id: lines.count, time: t, text: text))
        }
        while lines.last?.isInterlude == true { lines.removeLast() }
        return lines
    }
}

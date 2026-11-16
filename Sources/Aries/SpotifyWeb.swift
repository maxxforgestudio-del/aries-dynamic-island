import AppKit
import CryptoKit
import Network
import Security

/// Spotify Web API connection. This is what lets Aries see (and control) music
/// playing on your iPhone or any other Spotify Connect device.
/// Uses OAuth PKCE with a loopback redirect, so no client secret is stored.
final class SpotifyWeb: ObservableObject {
    static let shared = SpotifyWeb()
    static let redirectURI = "http://127.0.0.1:8898/callback"
    private static let port: NWEndpoint.Port = 8898
    private static let scopes = "user-read-playback-state user-read-currently-playing user-modify-playback-state user-library-read user-library-modify user-read-recently-played playlist-read-private playlist-read-collaborative playlist-modify-public playlist-modify-private user-follow-read user-follow-modify user-top-read"

    @Published private(set) var isConnected = false
    @Published private(set) var status = "Not connected"
    @Published private(set) var accountName: String?
    /// True while Aries waits for you to copy your Client ID in the Spotify dashboard.
    @Published private(set) var waitingForClientID = false
    var hasClientID: Bool { !clientID.isEmpty }
    private var clipTimer: Timer?
    private var clipCount = 0

    private var accessToken: String?
    private var expiry = Date.distantPast
    private var verifier = ""
    private var stateToken = ""
    private var listener: NWListener?

    private var clientID: String {
        Prefs.string(Prefs.spotifyClientID).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    init() {
        if Keychain.get("spotify.refresh") != nil {
            isConnected = true
            status = "Connected"
            Task { await loadProfile() }
        }
    }

    // MARK: Sign in

    /// Easy setup: copies the Redirect URI, opens the dashboard, then watches the clipboard —
    /// as soon as you copy your app's Client ID, Aries fills it in and connects by itself.
    func beginSetup() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Self.redirectURI, forType: .string)
        NSWorkspace.shared.open(URL(string: "https://developer.spotify.com/dashboard/create")!)
        waitingForClientID = true
        status = "Redirect URI copied — paste it in the dashboard, then copy your Client ID"
        clipCount = NSPasteboard.general.changeCount
        clipTimer?.invalidate()
        let started = Date()
        clipTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            if Date().timeIntervalSince(started) > 900 { self.stopWaiting(); return }
            let pb = NSPasteboard.general
            guard pb.changeCount != self.clipCount else { return }
            self.clipCount = pb.changeCount
            let text = (pb.string(forType: .string) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard Self.looksLikeClientID(text) else { return }
            self.stopWaiting()
            UserDefaults.standard.set(text, forKey: Prefs.spotifyClientID)
            self.status = "Got your Client ID — approve Aries in the browser"
            self.connect()
        }
    }

    func stopWaiting() {
        clipTimer?.invalidate(); clipTimer = nil
        waitingForClientID = false
    }

    static func looksLikeClientID(_ s: String) -> Bool {
        s.count == 32 && s.allSatisfy { $0.isHexDigit }
    }

    func connect() {
        guard !isConnected else { status = "Connected"; return }
        guard !clientID.isEmpty else { beginSetup(); return }
        verifier = Self.randomString(64)
        stateToken = Self.randomString(16)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL

        do { try startListener() } catch {
            status = "Couldn't open port 8898: \(error.localizedDescription)"
            return
        }

        var c = URLComponents(string: "https://accounts.spotify.com/authorize")!
        c.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: Self.redirectURI),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "state", value: stateToken),
            .init(name: "scope", value: Self.scopes),
        ]
        NSWorkspace.shared.open(c.url!)
        status = "Waiting for you to approve in the browser…"
    }

    func disconnect() {
        Keychain.delete("spotify.refresh")
        accessToken = nil
        expiry = .distantPast
        isConnected = false
        accountName = nil
        status = "Not connected"
    }

    private func startListener() throws {
        listener?.cancel()
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: Self.port)
        let l = try NWListener(using: params)
        l.newConnectionHandler = { [weak self] conn in
            conn.start(queue: .main)
            conn.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, _, _ in
                self?.handleCallback(data: data, conn: conn)
            }
        }
        l.start(queue: .main)
        listener = l
    }

    private func handleCallback(data: Data?, conn: NWConnection) {
        let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let path = request.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
        guard path.hasPrefix("/callback"), let comps = URLComponents(string: "http://127.0.0.1" + path) else {
            respond(conn, status: "404 Not Found", body: "")
            return
        }
        let q = Dictionary(uniqueKeysWithValues: (comps.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        listener?.cancel(); listener = nil

        guard q["state"] == stateToken, let code = q["code"] else {
            respond(conn, status: "400 Bad Request", body: page("Couldn't connect", q["error"] ?? "Please try again from Aries Settings."))
            status = "Sign-in was cancelled or failed"
            return
        }
        status = "Finishing up…"
        // Answer the browser only once the sign-in really worked, so it never says
        // "connected" while Aries isn't.
        Task {
            let ok = await exchange(code: code)
            await MainActor.run {
                self.respond(conn, status: ok ? "200 OK" : "400 Bad Request", body: ok
                    ? self.page("You're connected", "Spotify is now connected to Aries. You can close this tab.")
                    : self.page("Couldn't connect", "Check that the Redirect URI in your Spotify app is exactly \(Self.redirectURI), then try again from Aries."))
            }
        }
    }

    private func page(_ title: String, _ text: String) -> String {
        """
        <html><head><meta charset="utf-8"><title>Aries Dynamic Island</title></head>
        <body style="font-family:-apple-system,system-ui;background:#000;color:#fff;display:flex;align-items:center;justify-content:center;height:100vh;margin:0">
        <div style="text-align:center"><div style="width:120px;height:34px;border-radius:17px;background:#1c1c1e;margin:0 auto 24px"></div>
        <h1 style="font-weight:600">\(title)</h1><p style="color:#999">\(text)</p></div></body></html>
        """
    }

    private func respond(_ conn: NWConnection, status: String, body: String) {
        let res = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        conn.send(content: Data(res.utf8), completion: .contentProcessed { _ in conn.cancel() })
    }

    @discardableResult
    private func exchange(code: String) async -> Bool {
        let ok = await tokenRequest([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Self.redirectURI,
            "client_id": clientID,
            "code_verifier": verifier,
        ])
        await MainActor.run {
            self.isConnected = ok
            self.status = ok ? "Connected" : "Token exchange failed — check your Client ID and Redirect URI"
        }
        if ok { await loadProfile() }
        return ok
    }

    /// Returns true when we got an access token.
    private var lastTokenRejected = false
    private func tokenRequest(_ form: [String: String]) async -> Bool {
        var req = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var c = URLComponents()
        c.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        req.httpBody = c.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
            .data(using: .utf8)
        guard let (data, resp) = try? await URLSession.shared.data(for: req) else { lastTokenRejected = false; return false }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        lastTokenRejected = code == 400 || code == 401
        guard code == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String
        else { return false }
        accessToken = token
        expiry = Date().addingTimeInterval((json["expires_in"] as? Double) ?? 3600)
        if let refresh = json["refresh_token"] as? String { Keychain.set(refresh, for: "spotify.refresh") }
        return true
    }

    private func validToken() async -> String? {
        if let t = accessToken, expiry > Date().addingTimeInterval(30) { return t }
        guard let refresh = Keychain.get("spotify.refresh"), !clientID.isEmpty else { return nil }
        let ok = await tokenRequest(["grant_type": "refresh_token", "refresh_token": refresh, "client_id": clientID])
        if !ok {
            let rejected = lastTokenRejected
            await MainActor.run {
                if rejected {
                    // Spotify no longer accepts this sign-in: show Connect again instead of a stale "Connected".
                    Keychain.delete("spotify.refresh")
                    self.isConnected = false
                    self.accountName = nil
                    self.status = "Spotify signed you out — tap Connect to sign in again"
                } else {
                    self.status = "Can't reach Spotify right now"
                }
            }
            return nil
        }
        return accessToken
    }

    private func loadProfile() async {
        guard let (data, code) = await api("GET", "/me"), code == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let name = json["display_name"] as? String
        await MainActor.run { self.accountName = name }
    }

    // MARK: API

    private func api(_ method: String, _ path: String, body: [String: Any]? = nil) async -> (Data, Int)? {
        guard let token = await validToken() else { return nil }
        var req = URLRequest(url: URL(string: "https://api.spotify.com/v1" + path)!)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        } else if method != "GET" {
            req.setValue("0", forHTTPHeaderField: "Content-Length")
        }
        guard let (data, resp) = try? await URLSession.shared.data(for: req) else { return nil }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 { accessToken = nil }
        return (data, code)
    }

    private struct PlayerResponse: Decodable {
        struct Item: Decodable {
            struct Artist: Decodable { let name: String }
            struct Album: Decodable {
                struct Img: Decodable { let url: String; let width: Int? }
                let name: String
                let images: [Img]
            }
            let id: String?
            let name: String
            let duration_ms: Int
            let artists: [Artist]?
            let album: Album?
        }
        struct Device: Decodable { let name: String; let type: String; let volume_percent: Int? }
        let is_playing: Bool
        let shuffle_state: Bool?
        let repeat_state: String?
        let progress_ms: Int?
        let item: Item?
        let device: Device?
    }

    func fetchPlayback() async -> Snapshot? {
        let sent = Date()
        guard let (data, code) = await api("GET", "/me/player"), code == 200,
              let r = try? JSONDecoder().decode(PlayerResponse.self, from: data),
              let item = r.item else { return nil }
        let art = item.album?.images.max(by: { ($0.width ?? 0) < ($1.width ?? 0) })?.url
        let track = Track(
            id: item.id.map { "spotify:track:\($0)" } ?? item.name,
            title: item.name,
            artist: (item.artists ?? []).map(\.name).joined(separator: ", "),
            album: item.album?.name ?? "",
            duration: Double(item.duration_ms) / 1000,
            artworkURL: art.flatMap(URL.init(string:)))
        var snap = Snapshot(track: track, isPlaying: r.is_playing,
                            position: Double(r.progress_ms ?? 0) / 1000,
                            source: .spotifyRemote,
                            deviceName: r.device?.name, deviceType: r.device?.type,
                            // Spotify measured progress about halfway through the round trip.
                            fetchedAt: sent.addingTimeInterval(min(1.5, Date().timeIntervalSince(sent)) / 2))
        snap.shuffle = r.shuffle_state
        snap.repeatMode = r.repeat_state == "track" ? .one : (r.repeat_state == "context" ? .all : .off)
        snap.volume = r.device?.volume_percent
        return snap
    }

    // MARK: Library, queue, devices, search

    struct SimpleTrack: Identifiable, Equatable {
        let id: String
        let uri: String
        let title: String
        let artist: String
        let artURL: URL?
        let duration: Double
    }

    struct Device: Identifiable, Equatable {
        let id: String
        let name: String
        let type: String
        let isActive: Bool
        let volume: Int?
    }

    private static func parseTrack(_ t: [String: Any]) -> SimpleTrack? {
        guard let id = t["id"] as? String, let name = t["name"] as? String else { return nil }
        let artists = (t["artists"] as? [[String: Any]])?.compactMap { $0["name"] as? String }.joined(separator: ", ") ?? ""
        let images = ((t["album"] as? [String: Any])?["images"] as? [[String: Any]]) ?? []
        let small = images.min { ($0["width"] as? Int ?? 0) < ($1["width"] as? Int ?? 0) }?["url"] as? String
        return SimpleTrack(id: id, uri: t["uri"] as? String ?? "spotify:track:\(id)", title: name, artist: artists,
                           artURL: small.flatMap(URL.init(string:)),
                           duration: Double(t["duration_ms"] as? Int ?? 0) / 1000)
    }

    private func json(_ path: String) async -> Any? {
        guard let (data, code) = await api("GET", path), code == 200 else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    func queue() async -> [SimpleTrack] {
        guard let j = await json("/me/player/queue") as? [String: Any],
              let q = j["queue"] as? [[String: Any]] else { return [] }
        return q.compactMap(Self.parseTrack)
    }

    func recentlyPlayed() async -> [SimpleTrack] {
        guard let j = await json("/me/player/recently-played?limit=20") as? [String: Any],
              let items = j["items"] as? [[String: Any]] else { return [] }
        var seen = Set<String>()
        return items.compactMap { ($0["track"] as? [String: Any]).flatMap(Self.parseTrack) }
            .filter { seen.insert($0.id).inserted }
    }

    func search(_ q: String) async -> [SimpleTrack] {
        let enc = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
        guard let j = await json("/search?type=track&limit=10&q=\(enc)") as? [String: Any],
              let items = (j["tracks"] as? [String: Any])?["items"] as? [[String: Any]] else { return [] }
        return items.compactMap(Self.parseTrack)
    }

    func devices() async -> [Device] {
        guard let j = await json("/me/player/devices") as? [String: Any],
              let list = j["devices"] as? [[String: Any]] else { return [] }
        return list.compactMap { d in
            guard let id = d["id"] as? String, let name = d["name"] as? String else { return nil }
            return Device(id: id, name: name, type: d["type"] as? String ?? "",
                          isActive: d["is_active"] as? Bool ?? false, volume: d["volume_percent"] as? Int)
        }
    }

    func transfer(to deviceID: String) async -> Bool {
        guard let (_, code) = await api("PUT", "/me/player", body: ["device_ids": [deviceID], "play": true]) else { return false }
        return code < 300
    }

    /// Returns false when there is no active device to play on.
    func play(uri: String) async -> Bool {
        guard let (_, code) = await api("PUT", "/me/player/play", body: ["uris": [uri]]) else { return false }
        return code < 300
    }

    func isSaved(_ id: String) async -> Bool? {
        guard let arr = await json("/me/tracks/contains?ids=\(id)") as? [Bool] else { return nil }
        return arr.first
    }

    func setSaved(_ id: String, _ saved: Bool) async -> Bool {
        guard let (_, code) = await api(saved ? "PUT" : "DELETE", "/me/tracks?ids=\(id)") else { return false }
        return code < 300
    }

    // MARK: Artist, album, playlists, queue

    struct ArtistInfo: Equatable {
        let id: String
        let uri: String
        let name: String
        let imageURL: URL?
        let followers: Int?
        let genres: [String]
        var top: [SimpleTrack]
        var following: Bool?
    }

    struct AlbumInfo: Equatable {
        let id: String
        let uri: String
        let name: String
        let imageURL: URL?
        let year: String
        let label: String?
        let tracks: [SimpleTrack]
    }

    struct Playlist: Identifiable, Equatable {
        let id: String
        let uri: String
        let name: String
        let imageURL: URL?
        let count: Int?
        let mine: Bool
    }

    private var userID: String?

    /// The Spotify artist and album of a song. Uses the Spotify id when we have it,
    /// otherwise finds the song on Spotify by name (works for Apple Music songs too).
    func resolve(trackID: String?, title: String, artist: String) async -> (artist: String, album: String, track: String)? {
        var t: [String: Any]?
        if let id = trackID { t = await json("/tracks/\(id)") as? [String: Any] }
        if t == nil {
            let q = "track:\(title) artist:\(artist.components(separatedBy: ", ").first ?? artist)"
            let enc = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
            let j = await json("/search?type=track&limit=1&q=\(enc)") as? [String: Any]
            t = ((j?["tracks"] as? [String: Any])?["items"] as? [[String: Any]])?.first
        }
        guard let t, let tid = t["id"] as? String,
              let aid = (t["artists"] as? [[String: Any]])?.first?["id"] as? String,
              let alb = (t["album"] as? [String: Any])?["id"] as? String else { return nil }
        return (aid, alb, tid)
    }

    private static func bestImage(_ any: Any?) -> URL? {
        let imgs = (any as? [[String: Any]]) ?? []
        let pick = imgs.first { ($0["width"] as? Int ?? 0) <= 700 } ?? imgs.first
        return (pick?["url"] as? String).flatMap(URL.init(string:))
    }

    func artist(_ id: String) async -> ArtistInfo? {
        guard let a = await json("/artists/\(id)") as? [String: Any], let name = a["name"] as? String else { return nil }
        // Spotify closed "top tracks" and the old follow endpoints to apps in development mode (2026),
        // so fall back to search and the newer library endpoints when they're refused.
        var top: [SimpleTrack] = []
        if let topJ = await json("/artists/\(id)/top-tracks?market=from_token") as? [String: Any] {
            top = ((topJ["tracks"] as? [[String: Any]]) ?? []).compactMap(Self.parseTrack)
        }
        if top.isEmpty {
            let q = "artist:\"\(name)\"".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
            if let j = await json("/search?type=track&limit=10&q=\(q)") as? [String: Any],
               let items = (j["tracks"] as? [String: Any])?["items"] as? [[String: Any]] {
                // Only this artist's songs, most popular first.
                top = items.filter { (($0["artists"] as? [[String: Any]]) ?? []).contains { $0["id"] as? String == id } }
                    .sorted { ($0["popularity"] as? Int ?? 0) > ($1["popularity"] as? Int ?? 0) }
                    .compactMap(Self.parseTrack)
            }
        }
        var following = (await json("/me/library/contains?uris=spotify:artist:\(id)") as? [Bool])?.first
        if following == nil { following = (await json("/me/following/contains?type=artist&ids=\(id)") as? [Bool])?.first }
        return ArtistInfo(id: id, uri: a["uri"] as? String ?? "spotify:artist:\(id)", name: name,
                          imageURL: Self.bestImage(a["images"]),
                          followers: (a["followers"] as? [String: Any])?["total"] as? Int,
                          genres: (a["genres"] as? [String]) ?? [], top: Array(top.prefix(10)), following: following)
    }

    func album(_ id: String) async -> AlbumInfo? {
        guard let a = await json("/albums/\(id)") as? [String: Any], let name = a["name"] as? String else { return nil }
        let img = Self.bestImage(a["images"])
        let items = ((a["tracks"] as? [String: Any])?["items"] as? [[String: Any]]) ?? []
        let tracks: [SimpleTrack] = items.compactMap { t in
            guard let tid = t["id"] as? String, let n = t["name"] as? String else { return nil }
            let artists = (t["artists"] as? [[String: Any]])?.compactMap { $0["name"] as? String }.joined(separator: ", ") ?? ""
            return SimpleTrack(id: tid, uri: t["uri"] as? String ?? "spotify:track:\(tid)", title: n, artist: artists,
                               artURL: img, duration: Double(t["duration_ms"] as? Int ?? 0) / 1000)
        }
        return AlbumInfo(id: id, uri: a["uri"] as? String ?? "spotify:album:\(id)", name: name, imageURL: img,
                         year: String((a["release_date"] as? String ?? "").prefix(4)), label: a["label"] as? String,
                         tracks: tracks)
    }

    func playlists() async -> [Playlist] {
        if userID == nil, let me = await json("/me") as? [String: Any] { userID = me["id"] as? String }
        guard let j = await json("/me/playlists?limit=50") as? [String: Any],
              let items = j["items"] as? [[String: Any]] else { return [] }
        return items.compactMap { p in
            guard let id = p["id"] as? String, let name = p["name"] as? String else { return nil }
            let owner = (p["owner"] as? [String: Any])?["id"] as? String
            let count = ((p["tracks"] ?? p["items"]) as? [String: Any])?["total"] as? Int
            return Playlist(id: id, uri: p["uri"] as? String ?? "spotify:playlist:\(id)", name: name,
                            imageURL: Self.bestImage(p["images"]), count: count,
                            mine: owner == userID || (p["collaborative"] as? Bool ?? false))
        }
    }

    func add(uri: String, toPlaylist id: String) async -> Bool {
        // Spotify renamed /tracks to /items; try the new one first.
        for path in ["/playlists/\(id)/items", "/playlists/\(id)/tracks"] {
            if let (_, code) = await api("POST", path, body: ["uris": [uri]]), code < 300 { return true }
        }
        return false
    }

    func addToQueue(uri: String) async -> Bool {
        let enc = uri.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? uri
        guard let (_, code) = await api("POST", "/me/player/queue?uri=\(enc)") else { return false }
        return code < 300
    }

    func setFollowing(artist id: String, _ on: Bool) async -> Bool {
        if let (_, code) = await api(on ? "PUT" : "DELETE", "/me/library?uris=spotify:artist:\(id)"), code < 300 { return true }
        guard let (_, code) = await api(on ? "PUT" : "DELETE", "/me/following?type=artist&ids=\(id)") else { return false }
        return code < 300
    }

    func play(context: String, offset: String?) async -> Bool {
        var body: [String: Any] = ["context_uri": context]
        if let offset { body["offset"] = ["uri": offset] }
        guard let (_, code) = await api("PUT", "/me/player/play", body: body) else { return false }
        return code < 300
    }

    func setShuffle(_ on: Bool) async { _ = await api("PUT", "/me/player/shuffle?state=\(on)") }
    func setRepeat(_ m: RepeatMode) async {
        _ = await api("PUT", "/me/player/repeat?state=\(m == .one ? "track" : (m == .all ? "context" : "off"))")
    }
    func setVolume(_ v: Int) async { _ = await api("PUT", "/me/player/volume?volume_percent=\(max(0, min(100, v)))") }

    // Playback control requires Spotify Premium.
    func setPlaying(_ play: Bool) async { _ = await api("PUT", play ? "/me/player/play" : "/me/player/pause") }
    func skip(forward: Bool) async { _ = await api("POST", forward ? "/me/player/next" : "/me/player/previous") }
    func seek(to seconds: Double) async { _ = await api("PUT", "/me/player/seek?position_ms=\(Int(seconds * 1000))") }

    // MARK: Helpers

    private static func randomString(_ n: Int) -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var rng = SystemRandomNumberGenerator()
        return String((0..<n).map { _ in chars[Int(rng.next() % UInt64(chars.count))] })
    }
}

private extension Data {
    var base64URL: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

enum Keychain {
    private static let service = "app.aries.dynamicisland"

    // Tokens live in a private file (readable only by you) instead of the login keychain:
    // ad-hoc signed apps get a new keychain identity with every update, which made macOS
    // ask for your password after each update.
    private static var file: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Aries Dynamic Island", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        return dir.appendingPathComponent("credentials.plist")
    }
    private static let lock = NSLock()

    private static func load() -> [String: String] {
        (try? Data(contentsOf: file)).flatMap { try? PropertyListDecoder().decode([String: String].self, from: $0) } ?? [:]
    }
    private static func save(_ d: [String: String]) {
        guard let data = try? PropertyListEncoder().encode(d) else { return }
        try? data.write(to: file, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    static func set(_ value: String, for key: String) {
        lock.withLock { var d = load(); d[key] = value; save(d) }
    }

    static func get(_ key: String) -> String? {
        if let v = lock.withLock({ load()[key] }) { return v }
        // One-time move from the old keychain item — never shows a password prompt.
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            "u_AuthUI": "u_AuthUIF",   // kSecUseAuthenticationUI = Fail (no prompt)
        ]
        var out: AnyObject?
        // Turn keychain prompts off for this one read (SecKeychainSetUserInteractionAllowed).
        typealias SetUI = @convention(c) (DarwinBoolean) -> OSStatus
        let setUI = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "SecKeychainSetUserInteractionAllowed")
            .map { unsafeBitCast($0, to: SetUI.self) }
        _ = setUI?(false)
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        _ = setUI?(true)
        guard status == errSecSuccess, let d = out as? Data,
              let v = String(data: d, encoding: .utf8) else { return nil }
        set(v, for: key)
        return v
    }

    static func delete(_ key: String) {
        lock.withLock { var d = load(); d[key] = nil; save(d) }
    }
}

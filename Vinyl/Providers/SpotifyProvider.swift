import Foundation
import MusicKit
import AuthenticationServices
import CryptoKit
import UIKit

/// Spotify Web API with PKCE auth. Current playback is polled every 3s; control endpoints
/// require Spotify Premium and an active device. Set clientID from your own app at
/// developer.spotify.com (redirect URI: vinylplayer://callback).
final class SpotifyProvider: NSObject, MusicProvider, ASWebAuthenticationPresentationContextProviding {
    let kind = ProviderKind.spotify
    var onState: ((MusicState) -> Void)?
    static var clientID = "70897a5183fd4b5882d54b1614c42309"
    private let redirect = "vinylplayer://callback"
    private var token: String?
    private var refresh: String? { didSet { Keychain.set(refresh, "spotify.refresh") } }
    private var expiry = Date.distantPast
    private var timer: Timer?
    private var verifier = ""
    private var session: ASWebAuthenticationSession?   // must be retained until it finishes
    private var active = false                          // false after disconnect: drop late responses
    private(set) var granted = ""                     // scopes Spotify reports for the current token
    private var polling = false                         // one poll in flight at a time

    deinit { timer?.invalidate() }

    func authorize() async throws {
        guard !Self.clientID.isEmpty else {
            throw MusicError.notConfigured("Set SpotifyProvider.clientID from developer.spotify.com.")
        }
        verifier = Data((0..<48).map { _ in UInt8.random(in: 0...255) }).base64URL
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        var c = URLComponents(string: "https://accounts.spotify.com/authorize")!
        c.queryItems = [.init(name: "client_id", value: Self.clientID), .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: redirect), .init(name: "code_challenge_method", value: "S256"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "scope", value: "user-read-playback-state user-modify-playback-state user-read-currently-playing playlist-read-private playlist-read-collaborative")]
        let url = c.url!
        let cb: URL = try await withCheckedThrowingContinuation { cont in
            DispatchQueue.main.async {
                let s = ASWebAuthenticationSession(url: url, callbackURLScheme: "vinylplayer") { [weak self] u, e in
                    self?.session = nil
                    if let u { cont.resume(returning: u) } else { cont.resume(throwing: e ?? MusicError.denied) }
                }
                s.presentationContextProvider = self
                self.session = s
                // start() returns false if the session could not be shown; the handler never fires then.
                if !s.start() { self.session = nil; cont.resume(throwing: MusicError.denied) }
            }
        }
        guard let code = URLComponents(url: cb, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code" })?.value
        else { throw MusicError.denied }
        try await tokenRequest(["grant_type": "authorization_code", "code": code, "redirect_uri": redirect,
                                "client_id": Self.clientID, "code_verifier": verifier])
        await MainActor.run { startPolling() }
    }

    /// Only an explicit refusal from Spotify throws `MusicError.denied`; network trouble and
    /// server errors throw other errors so the caller keeps the saved login.
    private func tokenRequest(_ body: [String: String]) async throws {
        var r = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        r.httpMethod = "POST"
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        r.httpBody = body.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")" }
            .joined(separator: "&").data(using: .utf8)
        let (d, resp) = try await URLSession.shared.data(for: r)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
        guard status == 200, let t = j?["access_token"] as? String else {
            if status == 400 || status == 401 { throw MusicError.denied }
            throw URLError(.badServerResponse)
        }
        token = t
        if let sc = j?["scope"] as? String { granted = sc }
        if let rt = j?["refresh_token"] as? String { refresh = rt }
        expiry = Date().addingTimeInterval((j?["expires_in"] as? Double ?? 3600) - 60)
    }

    /// Reuse the stored refresh token so the user doesn't sign in on every launch.
    func restore() async throws {
        guard let rt = Keychain.get("spotify.refresh") else { throw MusicError.denied }
        refresh = rt
        try await tokenRequest(["grant_type": "refresh_token", "refresh_token": rt, "client_id": Self.clientID])
        await MainActor.run { startPolling() }
    }

    func disconnect() {
        active = false; timer?.invalidate(); timer = nil; token = nil; refresh = nil
        onState?(MusicState())
    }

    private func refreshIfNeeded() async {
        guard Date() > expiry, let rt = refresh else { return }
        do { try await tokenRequest(["grant_type": "refresh_token", "refresh_token": rt, "client_id": Self.clientID]) }
        catch { expiry = Date().addingTimeInterval(30) }   // back off instead of retrying every poll
    }

    private func call(_ method: String, _ path: String, body: Data? = nil, root: String = "/me/player") async -> (Data, Int)? {
        await refreshIfNeeded()
        guard active, let token else { return nil }
        var r = URLRequest(url: URL(string: "https://api.spotify.com/v1" + root + path)!)
        r.httpMethod = method
        if method != "GET" { r.httpBody = body ?? Data() }
        if body != nil { r.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (d, resp) = try? await URLSession.shared.data(for: r) else { return nil }
        return (d, (resp as? HTTPURLResponse)?.statusCode ?? 0)
    }
    private func settle(_ ms: UInt64 = 350) async { try? await Task.sleep(nanoseconds: ms * 1_000_000); await poll() }
    func play() async { _ = await call("PUT", "/play"); await settle() }
    func pause() async { _ = await call("PUT", "/pause"); await settle() }
    func next() async { _ = await call("POST", "/next"); await settle(500) }
    func previous() async { _ = await call("POST", "/previous"); await settle(500) }
    /// Jump to an "up next" row: skipping forward `n` times keeps the playlist/album context (Spotify has no direct jump).
    func skip(forward n: Int) async {
        for _ in 0..<max(1, min(n, 50)) { _ = await call("POST", "/next"); try? await Task.sleep(nanoseconds: 150_000_000) }
        await settle(500)
    }
    /// Adds a track to the end of the playback queue. Spotify has no "play next" call.
    func enqueue(uri: String) async -> String? {
        guard let (_, status) = await call("POST", "/queue?uri=" + (uri.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? uri)) else { return "Couldn't reach Spotify." }
        switch status {
        case 200..<300: return nil
        case 403: return "Spotify refused. Queueing needs Premium."
        case 404: return "No active Spotify device. Open Spotify and play something once."
        default: return "Spotify error \(status)."
        }
    }
    func setShuffle(_ on: Bool) async { _ = await call("PUT", "/shuffle?state=\(on)"); await settle() }
    func setRepeat(_ mode: RepeatMode) async {
        let v = mode == .all ? "context" : (mode == .one ? "track" : "off")
        _ = await call("PUT", "/repeat?state=\(v)"); await settle()
    }
    func seek(to t: TimeInterval) async { _ = await call("PUT", "/seek?position_ms=\(Int(t * 1000))"); await settle() }

    struct Playlist: Identifiable, Hashable {
        let id: String, name: String, owner: String, uri: String, imageURL: URL?
    }
    enum BrowseError: Error, Equatable { case needsReconnect, forbidden, failed }

    /// First 50 playlists. A token saved before playlist scopes were added gets 403: report `needsReconnect`.
    func playlists() async throws -> [Playlist] {
        guard granted.isEmpty || granted.contains("playlist-read-private") else { throw BrowseError.needsReconnect }
        guard let (d, status) = await call("GET", "/playlists?limit=50", root: "/me") else { throw BrowseError.failed }
        if status == 403 { throw BrowseError.needsReconnect }
        guard status == 200, let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let items = j["items"] as? [[String: Any]] else { throw BrowseError.failed }
        return items.compactMap { i in
            guard let id = i["id"] as? String, let uri = i["uri"] as? String else { return nil }
            let img = ((i["images"] as? [[String: Any]])?.first?["url"] as? String).flatMap(URL.init)
            return Playlist(id: id, name: i["name"] as? String ?? "Playlist",
                            owner: (i["owner"] as? [String: Any])?["display_name"] as? String ?? "", uri: uri, imageURL: img)
        }
    }

    struct QueueItem: Identifiable, Equatable {
        let id: Int, title: String, subtitle: String, imageURL: URL?
        var artwork: Artwork? = nil   // Apple Music queue rows
        static func == (a: QueueItem, b: QueueItem) -> Bool { a.id == b.id && a.title == b.title && a.subtitle == b.subtitle && a.imageURL == b.imageURL }
    }
    struct Queue: Equatable { var now: QueueItem?; var upNext: [QueueItem] }

    /// `GET /me/player/queue`. Items may be tracks or episodes, so every field is optional.
    func queue() async throws -> Queue {
        guard let (d, status) = await call("GET", "/queue") else { throw BrowseError.failed }
        if status == 401 || status == 403 { throw BrowseError.needsReconnect }
        guard status == 200, let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { throw BrowseError.failed }
        func item(_ o: [String: Any]?, _ n: Int) -> QueueItem? {
            guard let o, let title = o["name"] as? String else { return nil }
            let show = o["show"] as? [String: Any]
            let by = (o["artists"] as? [[String: Any]])?.compactMap { $0["name"] as? String }.joined(separator: ", ")
                ?? (show?["name"] as? String) ?? ""
            let imgs = ((o["album"] as? [String: Any])?["images"] as? [[String: Any]]) ?? (o["images"] as? [[String: Any]])
                ?? (show?["images"] as? [[String: Any]])
            return QueueItem(id: n, title: title, subtitle: by, imageURL: (imgs?.first?["url"] as? String).flatMap(URL.init))
        }
        let up = (j["queue"] as? [[String: Any]] ?? []).enumerated().compactMap { item($1, $0 + 1) }
        return Queue(now: item(j["currently_playing"] as? [String: Any], 0), upNext: up)
    }

    private static func song(_ o: [String: Any]?) -> SongItem? {
        guard let o, let uri = o["uri"] as? String, uri.hasPrefix("spotify:track:"), let title = o["name"] as? String else { return nil }
        let by = (o["artists"] as? [[String: Any]])?.compactMap { $0["name"] as? String }.joined(separator: ", ") ?? ""
        let imgs = (o["album"] as? [String: Any])?["images"] as? [[String: Any]] ?? []
        let url = ((imgs.count > 1 ? imgs[1] : imgs.first)?["url"] as? String).flatMap(URL.init)
        return SongItem(id: uri, title: title, artist: by, imageURL: url)
    }

    /// Songs of a playlist. Spotify's dev-mode rules refuse this for playlists you do not own (403 -> .forbidden).
    func tracks(playlistID: String) async throws -> [SongItem] {
        var res = await call("GET", "/playlists/\(playlistID)/items?limit=100", root: "")
        if res?.1 == 404 { res = await call("GET", "/playlists/\(playlistID)/tracks?limit=100", root: "") }
        guard let (d, status) = res else { throw BrowseError.failed }
        if status == 401 { throw BrowseError.needsReconnect }
        if status == 403 { throw BrowseError.forbidden }
        guard status == 200, let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let items = j["items"] as? [[String: Any]] else { throw BrowseError.failed }
        return items.compactMap { Self.song(($0["track"] ?? $0["item"]) as? [String: Any]) }
    }

    /// Song search.
    func search(_ q: String) async throws -> [SongItem] {
        let enc = q.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? q
        guard let (d, status) = await call("GET", "/search?q=\(enc)&type=track&limit=10", root: "") else { throw BrowseError.failed }
        guard status == 200, let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let items = (j["tracks"] as? [String: Any])?["items"] as? [[String: Any]] else { throw BrowseError.failed }
        return items.compactMap { Self.song($0) }
    }

    /// Plays one song, inside `context` (a playlist URI) when given so the rest of it follows.
    func play(uri: String, context: String?) async -> String? {
        var body: [String: Any] = ["uris": [uri]]
        if let context { body = ["context_uri": context, "offset": ["uri": uri] as [String: Any]] }
        let data = try? JSONSerialization.data(withJSONObject: body)
        guard let (_, status) = await call("PUT", "/play", body: data) else { return "Couldn't reach Spotify." }
        await settle(600)
        switch status {
        case 200..<300: return nil
        case 403: return "Spotify refused. Playback control needs Premium."
        case 404: return "No active Spotify device. Open Spotify and play something once."
        default: return "Spotify error \(status)."
        }
    }

    /// Starts a playlist. Returns a message to show when Spotify refuses (no Premium / no active device).
    func play(contextURI: String) async -> String? {
        let body = try? JSONSerialization.data(withJSONObject: ["context_uri": contextURI])
        guard let (_, status) = await call("PUT", "/play", body: body) else { return "Couldn't reach Spotify." }
        await settle(600)
        switch status {
        case 200..<300: return nil
        case 403: return "Spotify refused. Playback control needs Premium."
        case 404: return "No active Spotify device. Open Spotify and play something once."
        default: return "Spotify error \(status)."
        }
    }

    // MARK: artist / album browsing (tap the artist or title on the player)
    private static func album(_ o: [String: Any]?) -> CatalogAlbum? {
        guard let o, let id = o["id"] as? String, let name = o["name"] as? String else { return nil }
        let imgs = o["images"] as? [[String: Any]] ?? []
        let url = ((imgs.count > 1 ? imgs[1] : imgs.first)?["url"] as? String).flatMap(URL.init)
        let by = (o["artists"] as? [[String: Any]])?.compactMap { $0["name"] as? String }.joined(separator: ", ") ?? ""
        return CatalogAlbum(id: id, title: name, artist: by, year: String((o["release_date"] as? String ?? "").prefix(4)), imageURL: url)
    }
    private func getJSON(_ path: String) async throws -> [String: Any] {
        guard let (d, status) = await call("GET", path, root: "") else { throw BrowseError.failed }
        if status == 401 { throw BrowseError.needsReconnect }
        if status == 403 { throw BrowseError.forbidden }
        guard status == 200, let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { throw BrowseError.failed }
        return j
    }
    private static func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? s }

    /// Albums and singles of an artist, newest first. Uses the artist ID when known, else the best name match.
    func artistAlbums(name: String, id: String?) async throws -> [CatalogAlbum] {
        var artistID = id
        if artistID == nil {
            let j = try await getJSON("/search?q=\(Self.enc(name))&type=artist&limit=1")
            artistID = ((j["artists"] as? [String: Any])?["items"] as? [[String: Any]])?.first?["id"] as? String
        }
        guard let artistID else { return [] }
        let j = try await getJSON("/artists/\(artistID)/albums?include_groups=album,single&limit=50")
        var seen = Set<String>()
        return (j["items"] as? [[String: Any]] ?? []).compactMap { Self.album($0) }
            .filter { seen.insert($0.title.lowercased()).inserted }
            .sorted { $0.year > $1.year }
    }

    func findAlbum(title: String, artist: String, id: String?) async throws -> CatalogAlbum? {
        if let id { return Self.album(try await getJSON("/albums/\(id)")) }
        let j = try await getJSON("/search?q=\(Self.enc("album:\(title) artist:\(artist)"))&type=album&limit=1")
        return Self.album(((j["albums"] as? [String: Any])?["items"] as? [[String: Any]])?.first)
    }

    func albumTracks(_ a: CatalogAlbum) async throws -> [SongItem] {
        let j = try await getJSON("/albums/\(a.id)/tracks?limit=50")
        return (j["items"] as? [[String: Any]] ?? []).compactMap { o in
            guard let uri = o["uri"] as? String, let t = o["name"] as? String else { return nil }
            let by = (o["artists"] as? [[String: Any]])?.compactMap { $0["name"] as? String }.joined(separator: ", ") ?? ""
            return SongItem(id: uri, title: t, artist: by, imageURL: a.imageURL)
        }
    }

    /// Plays the album, starting at `start` when given.
    func play(album a: CatalogAlbum, start: SongItem?) async -> String? {
        if let start { return await play(uri: start.id, context: "spotify:album:\(a.id)") }
        return await play(contextURI: "spotify:album:\(a.id)")
    }

    private func startPolling() {
        active = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in Task { await self?.poll() } }
        Task { await poll() }
    }

    private func poll() async {
        guard active, !polling else { return }
        polling = true; defer { polling = false }
        // Errors (401, 429, 5xx, offline) keep the last known state instead of blanking the record.
        guard let (d, status) = await call("GET", ""), active else { return }
        if status == 204 { onState?(MusicState(provider: .spotify)); return }   // no active device
        guard status == 200, let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return }
        // Ads, podcasts and local files may have no item: report "connected, nothing playing".
        guard let item = j["item"] as? [String: Any] else { onState?(MusicState(provider: .spotify)); return }
        let album = item["album"] as? [String: Any]
        let img = ((album?["images"] as? [[String: Any]])?.first?["url"] as? String).flatMap(URL.init)
        let artists = (item["artists"] as? [[String: Any]])?.compactMap { $0["name"] as? String }.joined(separator: ", ") ?? ""
        var st = MusicState(provider: .spotify)
        st.isPlaying = j["is_playing"] as? Bool ?? false
        st.shuffle = j["shuffle_state"] as? Bool ?? false
        st.repeatMode = (j["repeat_state"] as? String).map { $0 == "context" ? .all : ($0 == "track" ? .one : .off) } ?? .off
        st.progress = (j["progress_ms"] as? Double ?? 0) / 1000
        let title = item["name"] as? String ?? ""
        // Local files have no id; fall back to title+artist so consecutive ones still count as a change.
        let id = (item["id"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "\(title)|\(artists)"
        st.track = Track(id: id, title: title, artist: artists,
                         album: album?["name"] as? String ?? "", artworkURL: img,
                         duration: (item["duration_ms"] as? Double ?? 0) / 1000,
                         artistID: (item["artists"] as? [[String: Any]])?.first?["id"] as? String,
                         albumID: album?["id"] as? String)
        onState?(st)
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.first?.windows.first ?? ASPresentationAnchor()
    }
}

private extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

enum Keychain {
    static func get(_ k: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: k,
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    static func set(_ v: String?, _ k: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: k]
        SecItemDelete(q as CFDictionary)
        if let v { var a = q; a[kSecValueData as String] = Data(v.utf8); SecItemAdd(a as CFDictionary, nil) }
    }
}

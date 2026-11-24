import Foundation
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
    func seek(to t: TimeInterval) async { _ = await call("PUT", "/seek?position_ms=\(Int(t * 1000))"); await settle() }

    struct Playlist: Identifiable, Equatable {
        let id: String, name: String, owner: String, uri: String, imageURL: URL?
    }
    enum BrowseError: Error, Equatable { case needsReconnect, failed }

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
        st.progress = (j["progress_ms"] as? Double ?? 0) / 1000
        let title = item["name"] as? String ?? ""
        // Local files have no id; fall back to title+artist so consecutive ones still count as a change.
        let id = (item["id"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "\(title)|\(artists)"
        st.track = Track(id: id, title: title, artist: artists,
                         album: album?["name"] as? String ?? "", artworkURL: img,
                         duration: (item["duration_ms"] as? Double ?? 0) / 1000)
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

import Foundation
import AuthenticationServices
import CryptoKit

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
            .init(name: "scope", value: "user-read-playback-state user-modify-playback-state user-read-currently-playing")]
        let url = c.url!
        let cb: URL = try await withCheckedThrowingContinuation { cont in
            DispatchQueue.main.async {
                let s = ASWebAuthenticationSession(url: url, callbackURLScheme: "vinylplayer") { u, e in
                    if let u { cont.resume(returning: u) } else { cont.resume(throwing: e ?? MusicError.denied) }
                }
                s.presentationContextProvider = self
                s.start()
            }
        }
        guard let code = URLComponents(url: cb, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code" })?.value
        else { throw MusicError.denied }
        try await tokenRequest(["grant_type": "authorization_code", "code": code, "redirect_uri": redirect,
                                "client_id": Self.clientID, "code_verifier": verifier])
        await MainActor.run { startPolling() }
    }

    private func tokenRequest(_ body: [String: String]) async throws {
        var r = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        r.httpMethod = "POST"
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        r.httpBody = body.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")" }
            .joined(separator: "&").data(using: .utf8)
        let (d, _) = try await URLSession.shared.data(for: r)
        guard let j = try JSONSerialization.jsonObject(with: d) as? [String: Any], let t = j["access_token"] as? String
        else { throw MusicError.denied }
        token = t
        if let rt = j["refresh_token"] as? String { refresh = rt }
        expiry = Date().addingTimeInterval((j["expires_in"] as? Double ?? 3600) - 60)
    }

    func disconnect() { timer?.invalidate(); token = nil; refresh = nil; onState?(MusicState()) }

    private func call(_ method: String, _ path: String) async -> Data? {
        if Date() > expiry, let rt = refresh {
            try? await tokenRequest(["grant_type": "refresh_token", "refresh_token": rt, "client_id": Self.clientID])
        }
        guard let token else { return nil }
        var r = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player" + path)!)
        r.httpMethod = method
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try? await URLSession.shared.data(for: r).0
    }
    func play() async { _ = await call("PUT", "/play"); await poll() }
    func pause() async { _ = await call("PUT", "/pause"); await poll() }
    func next() async { _ = await call("POST", "/next"); try? await Task.sleep(nanoseconds: 400_000_000); await poll() }
    func previous() async { _ = await call("POST", "/previous"); try? await Task.sleep(nanoseconds: 400_000_000); await poll() }
    func seek(to t: TimeInterval) async { _ = await call("PUT", "/seek?position_ms=\(Int(t * 1000))"); await poll() }

    private func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in Task { await self?.poll() } }
        Task { await poll() }
    }

    private func poll() async {
        guard let d = await call("GET", ""),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let item = j["item"] as? [String: Any] else { return }
        let album = item["album"] as? [String: Any]
        let img = ((album?["images"] as? [[String: Any]])?.first?["url"] as? String).flatMap(URL.init)
        let artists = (item["artists"] as? [[String: Any]])?.compactMap { $0["name"] as? String }.joined(separator: ", ") ?? ""
        var st = MusicState(provider: .spotify)
        st.isPlaying = j["is_playing"] as? Bool ?? false
        st.progress = (j["progress_ms"] as? Double ?? 0) / 1000
        st.track = Track(id: item["id"] as? String ?? "", title: item["name"] as? String ?? "", artist: artists,
                         album: album?["name"] as? String ?? "", artworkURL: img,
                         duration: (item["duration_ms"] as? Double ?? 0) / 1000)
        onState?(st)
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { ASPresentationAnchor() }
}

private extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

enum Keychain {
    static func set(_ v: String?, _ k: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: k]
        SecItemDelete(q as CFDictionary)
        if let v { var a = q; a[kSecValueData as String] = Data(v.utf8); SecItemAdd(a as CFDictionary, nil) }
    }
}

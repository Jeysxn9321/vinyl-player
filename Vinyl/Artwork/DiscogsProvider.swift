import Foundation

/// The app ships no Discogs key. Two ways to turn it on from Settings: the user's OWN personal access token (kept in the
/// device Keychain, sent only to api.discogs.com), or a proxy URL (backend/discogs-proxy) that holds a key/secret.
/// NOT RUN LIVE: written against the proxy contract in backend/discogs-proxy/README.md, never exercised against Discogs.
///
/// Contract: GET <proxy>/lookup?artist=…&album=… -> { "releases": [ { "id": 123, "title": "…", "year": "1979",
///   "format": "Vinyl, LP", "catno": "…", "country": "…", "uri": "https://www.discogs.com/release/123",
///   "images": [ { "type": "primary"|"secondary", "url": "https://…", "label": false } ] } ] }
/// Discogs images are only `primary` / `secondary`; none is a guaranteed centre label, so every Discogs image is
/// `.unverified` and shown as an edition image.
struct DiscogsProvider: ArtworkProvider {
    let source = ArtworkSource.discogs
    enum Mode { case token(String), proxy(URL) }
    let mode: Mode

    static let tokenKey = "discogs.token"
    static var token: String? {
        guard let t = Keychain.get(tokenKey)?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }
    static var proxyURL: URL? {
        guard let s = UserDefaults.standard.string(forKey: "art.discogsProxy"), let u = URL(string: s.trimmingCharacters(in: .whitespaces)),
              u.scheme == "https" else { return nil }
        return u
    }
    /// The user's own personal access token wins; otherwise the optional proxy; otherwise Discogs is off.
    static var configured: Mode? {
        if let t = token { return .token(t) }
        if let u = proxyURL { return .proxy(u) }
        return nil
    }

    /// One authenticated call, for the Settings status line. Returns nil when OK, else a short message.
    static func checkToken(_ t: String) async -> String? {
        var r = ArtworkNet.request(URL(string: "https://api.discogs.com/oauth/identity")!)
        r.setValue("Discogs token=\(t)", forHTTPHeaderField: "Authorization")
        guard let (_, resp) = try? await ArtworkNet.session.data(for: r), let h = resp as? HTTPURLResponse else { return "Couldn't reach Discogs." }
        switch h.statusCode {
        case 200: return nil
        case 401: return "Discogs rejected this token."
        default: return "Discogs answered HTTP \(h.statusCode)."
        }
    }

    // Direct-mode response shapes (api.discogs.com).
    struct SearchResp: Decodable { var results: [Hit]; struct Hit: Decodable { var id: Int } }
    struct ReleaseResp: Decodable {
        var id: Int; var title: String?; var year: Int?; var country: String?; var uri: String?
        var formats: [Fmt]?; var labels: [Lab]?; var images: [Image]?
        struct Fmt: Decodable { var name: String?; var descriptions: [String]? }
        struct Lab: Decodable { var catno: String? }
        struct Image: Decodable { var type: String?; var uri: String? }
        var asRel: Response.Rel {
            let fmt = (formats ?? []).map { ([$0.name].compactMap { $0 } + ($0.descriptions ?? [])).joined(separator: ", ") }.joined(separator: " + ")
            return .init(id: id, title: title, year: year.map(String.init), format: fmt.isEmpty ? nil : fmt, catno: labels?.first?.catno,
                         country: country, uri: uri, images: (images ?? []).compactMap { i in i.uri.map { .init(type: i.type, url: $0) } })
        }
    }

    struct Response: Decodable {
        var releases: [Rel]
        struct Rel: Decodable {
            var id: Int
            var title: String?
            var year: String?
            var format: String?
            var catno: String?
            var country: String?
            var uri: String?
            var images: [Img]?
        }
        struct Img: Decodable { var type: String?; var url: String }
    }

    private func apiGet(_ url: URL, token: String) async throws -> Data {
        var r = ArtworkNet.request(url)                                   // token goes only to api.discogs.com
        r.setValue("Discogs token=\(token)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await ArtworkNet.session.data(for: r)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw ArtworkError.http(code) }
        return data
    }

    func variants(for q: AlbumQuery) async throws -> [ArtworkVariant] {
        let rels: [Response.Rel]
        switch mode {
        case .proxy(let proxy):
            var c = URLComponents(url: proxy.appendingPathComponent("lookup"), resolvingAgainstBaseURL: false)!
            c.queryItems = [URLQueryItem(name: "artist", value: q.artist), URLQueryItem(name: "album", value: Matching.baseTitle(q.album))]
            let (data, resp) = try await ArtworkNet.session.data(for: ArtworkNet.request(c.url!))
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200 else { throw ArtworkError.http(code) }
            rels = try JSONDecoder().decode(Response.self, from: data).releases
        case .token(let t):
            var c = URLComponents(string: "https://api.discogs.com/database/search")!
            c.queryItems = [.init(name: "artist", value: q.artist), .init(name: "release_title", value: Matching.baseTitle(q.album)),
                            .init(name: "type", value: "release"), .init(name: "format", value: "Vinyl"), .init(name: "per_page", value: "5")]
            let hits = try JSONDecoder().decode(SearchResp.self, from: try await apiGet(c.url!, token: t)).results
            var got: [Response.Rel] = []
            for h in hits.prefix(4) {                                      // 60 authenticated requests/min: stay small
                guard let d = try? await apiGet(URL(string: "https://api.discogs.com/releases/\(h.id)")!, token: t),
                      let r = try? JSONDecoder().decode(ReleaseResp.self, from: d) else { continue }
                got.append(r.asRel)
            }
            rels = got
        }
        var out: [ArtworkVariant] = []
        for r in rels {
            let conf = Matching.confidence(query: q, artist: q.artist, title: r.title ?? q.album, isVinyl: (r.format ?? "").localizedCaseInsensitiveContains("vinyl"), date: r.year, barcode: nil)
            for (i, img) in (r.images ?? []).enumerated() {
                guard let u = Matching.secure(img.url) else { continue }
                out.append(ArtworkVariant(id: "discogs:\(r.id):\(i)", kind: .edition, verification: .unverified, source: .discogs,
                                          imageURL: u, fullURL: u, releaseID: "\(r.id)", editionTitle: r.title, year: r.year,
                                          format: r.format, catalogNumber: r.catno, country: r.country, confidence: conf,
                                          detail: img.type, sourceURL: r.uri.flatMap(URL.init(string:))))
            }
        }
        return out
    }
}

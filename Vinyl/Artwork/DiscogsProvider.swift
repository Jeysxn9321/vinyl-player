import Foundation

/// Discogs needs a registered application's key/secret, so Lunara never calls it directly: the secrets live on a
/// small proxy (see backend/discogs-proxy). The provider is OFF until the proxy URL is set in Settings.
/// NOT RUN LIVE: written against the proxy contract in backend/discogs-proxy/README.md, never exercised against Discogs.
///
/// Contract: GET <proxy>/lookup?artist=…&album=… -> { "releases": [ { "id": 123, "title": "…", "year": "1979",
///   "format": "Vinyl, LP", "catno": "…", "country": "…", "uri": "https://www.discogs.com/release/123",
///   "images": [ { "type": "primary"|"secondary", "url": "https://…", "label": false } ] } ] }
/// Discogs images are only `primary` / `secondary`; none is a guaranteed centre label, so every Discogs image is
/// `.unverified` and shown as an edition image.
struct DiscogsProvider: ArtworkProvider {
    let source = ArtworkSource.discogs
    let proxy: URL

    static var configured: URL? {
        guard let s = UserDefaults.standard.string(forKey: "art.discogsProxy"), let u = URL(string: s.trimmingCharacters(in: .whitespaces)),
              u.scheme == "https" else { return nil }
        return u
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

    func variants(for q: AlbumQuery) async throws -> [ArtworkVariant] {
        var c = URLComponents(url: proxy.appendingPathComponent("lookup"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "artist", value: q.artist), URLQueryItem(name: "album", value: Matching.baseTitle(q.album))]
        let (data, resp) = try await ArtworkNet.session.data(for: ArtworkNet.request(c.url!))
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw ArtworkError.http(code) }
        let rels = try JSONDecoder().decode(Response.self, from: data).releases
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

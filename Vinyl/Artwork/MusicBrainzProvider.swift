import Foundation

/// A source of vinyl artwork. Providers are independent: add one by conforming and listing it in `ArtworkCenter`.
protocol ArtworkProvider: Sendable {
    var source: ArtworkSource { get }
    /// Throws on network/service failure (so the caller does not cache a failure as "nothing exists").
    func variants(for query: AlbumQuery) async throws -> [ArtworkVariant]
}

enum ArtworkNet {
    /// MusicBrainz requires an identifying User-Agent. Deliberately generic: no personal details.
    static let userAgent = "Lunara/1.0 (iOS vinyl player; +https://github.com/Jeysxn9321/vinyl-player)"

    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 15
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    static func request(_ url: URL) -> URLRequest {
        var r = URLRequest(url: url)
        r.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        return r
    }
}

/// MusicBrainz allows about one request per second per client; this serialises and spaces them.
actor RateLimiter {
    private let gap: TimeInterval
    private var next = Date.distantPast
    init(gap: TimeInterval) { self.gap = gap }
    func wait() async {
        let now = Date()
        let start = max(now, next)
        next = start.addingTimeInterval(gap)
        let d = start.timeIntervalSince(now)
        if d > 0 { try? await Task.sleep(nanoseconds: UInt64(d * 1_000_000_000)) }
    }
}

enum ArtworkError: Error { case http(Int), cancelled }

struct MusicBrainzProvider: ArtworkProvider {
    let source = ArtworkSource.musicBrainz
    private static let limiter = RateLimiter(gap: 1.1)
    private static let caaLimiter = RateLimiter(gap: 0.3)

    /// Retries 503/429 (MusicBrainz answers 503 when busy, seen in real use) with backoff.
    private func fetch(_ url: URL, limiter: RateLimiter, retries: Int = 3) async throws -> Data? {
        var attempt = 0
        while true {
            try Task.checkCancellation()
            await limiter.wait()
            let (data, resp) = try await ArtworkNet.session.data(for: ArtworkNet.request(url))
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code == 200 { return data }
            if code == 404 { return nil }                       // e.g. a release without a Cover Art Archive index
            if (code == 503 || code == 429), attempt < retries {
                attempt += 1
                try await Task.sleep(nanoseconds: UInt64(Double(attempt) * 3 * 1_000_000_000))
                continue
            }
            throw ArtworkError.http(code)
        }
    }

    private func mb(_ path: String, _ items: [URLQueryItem]) -> URL {
        var c = URLComponents(string: "https://musicbrainz.org/ws/2/\(path)")!
        c.queryItems = items + [URLQueryItem(name: "fmt", value: "json")]
        return c.url!
    }

    func variants(for q: AlbumQuery) async throws -> [ArtworkVariant] {
        let base = Matching.baseTitle(q.album)
        let esc = { (s: String) in s.replacingOccurrences(of: "\"", with: " ") }
        let search = mb("release-group", [
            URLQueryItem(name: "query", value: "releasegroup:\"\(esc(base))\" AND artistname:\"\(esc(q.artist))\""),
            URLQueryItem(name: "limit", value: "5")])
        guard let sd = try await fetch(search, limiter: Self.limiter),
              let groups = try? JSONDecoder().decode(MBReleaseGroupSearch.self, from: sd).releaseGroups,
              let group = Matching.pickGroup(groups, query: q) else { return [] }

        let rel = mb("release", [URLQueryItem(name: "release-group", value: group.id),
                                 URLQueryItem(name: "inc", value: "media+labels"),
                                 URLQueryItem(name: "limit", value: "100")])
        guard let rd = try await fetch(rel, limiter: Self.limiter),
              let releases = try? JSONDecoder().decode(MBReleaseList.self, from: rd).releases else { return [] }

        var out: [ArtworkVariant] = []
        for (r, conf) in Matching.candidateReleases(releases, group: group, query: q) {
            guard let url = URL(string: "https://coverartarchive.org/release/\(r.id)"),
                  let data = try await fetch(url, limiter: Self.caaLimiter),
                  let index = try? JSONDecoder().decode(CAAIndex.self, from: data) else { continue }
            out += Matching.variants(release: r, group: group, index: index, confidence: conf, query: q)
        }
        return Matching.rank(out)
    }
}

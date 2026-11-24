import SwiftUI

/// Lyrics from LRCLIB (https://lrclib.net), a free community database. Neither Spotify nor Apple Music gives third-party
/// apps their lyrics, so a song missing from LRCLIB simply has none here. Time-synced when LRCLIB has timestamps.
struct LyricLine: Identifiable, Equatable {
    let id: Int
    var time: TimeInterval?
    var text: String
}

enum LyricsLoader {
    enum Result: Equatable { case lines([LyricLine], synced: Bool), instrumental, none }
    private static var cache: [String: Result] = [:]

    static func load(_ t: Track) async -> Result {
        let key = "\(t.artist)|\(t.title)|\(t.album)"
        if let c = cache[key] { return c }
        guard let r = await fetch(t) else { return .none }   // network error: don't cache, allow retry
        cache[key] = r
        return r
    }

    private struct Hit: Decodable {
        var instrumental: Bool?; var plainLyrics: String?; var syncedLyrics: String?
        var trackName: String?; var duration: Double?
    }

    private static func request(_ path: String, _ q: [String: String]) async -> (Data, Int)? {
        var c = URLComponents(string: "https://lrclib.net/api/\(path)")!
        c.queryItems = q.map { .init(name: $0.key, value: $0.value) }
        var r = URLRequest(url: c.url!)
        r.setValue("Lunara/1.0 (https://github.com/Jeysxn9321/vinyl-player)", forHTTPHeaderField: "User-Agent")
        r.timeoutInterval = 15
        guard let (d, resp) = try? await URLSession.shared.data(for: r), let h = resp as? HTTPURLResponse else { return nil }
        return (d, h.statusCode)
    }

    private static func fetch(_ t: Track) async -> Result? {
        let artist = t.artist.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? t.artist
        var q = ["artist_name": artist, "track_name": t.title]
        if !t.album.isEmpty { q["album_name"] = t.album }
        if t.duration > 0 { q["duration"] = String(Int(t.duration.rounded())) }
        guard let (d, status) = await request("get", q) else { return nil }
        var hit: Hit?
        if status == 200 { hit = try? JSONDecoder().decode(Hit.self, from: d) }
        else if status == 404 {
            // Exact match failed (album name / duration differ): fall back to a looser search.
            guard let (sd, ss) = await request("search", ["artist_name": artist, "track_name": t.title]), ss == 200 else { return ss404(status) }
            let hits = (try? JSONDecoder().decode([Hit].self, from: sd)) ?? []
            hit = hits.first { t.duration <= 0 || abs(($0.duration ?? 0) - t.duration) < 6 } ?? hits.first
        } else { return nil }
        guard let hit else { return Result.none }
        if hit.instrumental == true { return .instrumental }
        if let s = hit.syncedLyrics, !s.isEmpty {
            let lines = parseLRC(s)
            if !lines.isEmpty { return .lines(lines, synced: true) }
        }
        if let p = hit.plainLyrics, !p.isEmpty {
            let lines = p.components(separatedBy: "\n").enumerated().map { LyricLine(id: $0.offset, time: nil, text: $0.element) }
            return .lines(lines, synced: false)
        }
        return Result.none
    }
    private static func ss404(_ s: Int) -> Result? { s == 404 ? Result.none : nil }

    static func parseLRC(_ s: String) -> [LyricLine] {
        var out: [LyricLine] = []
        for raw in s.components(separatedBy: "\n") {
            guard raw.hasPrefix("["), let close = raw.firstIndex(of: "]") else { continue }
            let stamp = raw[raw.index(after: raw.startIndex)..<close].split(separator: ":")
            guard stamp.count == 2, let mm = Double(stamp[0]), let ss = Double(stamp[1]) else { continue }
            let text = raw[raw.index(after: close)...].trimmingCharacters(in: .whitespaces)
            out.append(LyricLine(id: out.count, time: mm * 60 + ss, text: text))
        }
        return out
    }
}

struct LyricsView: View {
    @ObservedObject var m: PlayerModel
    @Environment(\.dismiss) private var dismiss
    @State private var result: LyricsLoader.Result?
    @State private var failed = false
    private var demo: Bool { CommandLine.arguments.contains("-demo") }

    static let demoLines: [LyricLine] = [
        "Demo lyrics for screenshots only", "Not a real song", "Just some sample words", "To show the layout",
        "The current line is bright", "The others stay soft", "Tap a line to jump there",
    ].enumerated().map { LyricLine(id: $0.offset, time: Double($0.offset) * 12, text: $0.element) }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                content
            }
            .navigationTitle(m.state.track?.title ?? "Lyrics").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
        }
        .preferredColorScheme(.dark)
        .task(id: m.state.track?.id) { await load() }
    }

    @ViewBuilder var content: some View {
        if let result {
            switch result {
            case .instrumental: note("Instrumental")
            case .none: note("No lyrics found for this song.\nLyrics come from LRCLIB; neither Spotify nor Apple Music share theirs with other apps.")
            case .lines(let lines, let synced): lyrics(lines, synced: synced)
            }
        } else if failed { note("Couldn't reach the lyrics service. Check your connection.") }
        else { ProgressView() }
    }

    func note(_ s: String) -> some View {
        Text(s).foregroundStyle(.white.opacity(0.6)).multilineTextAlignment(.center).padding(32)
    }

    func lyrics(_ lines: [LyricLine], synced: Bool) -> some View {
        let now = m.state.progress
        let current = synced ? lines.lastIndex { ($0.time ?? .infinity) <= now + 0.25 } : nil
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(lines.enumerated()), id: \.element.id) { i, l in
                        let on = !synced || i == current
                        Text(l.text.isEmpty ? "♪" : l.text)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.white.opacity(on ? 1 : 0.35))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture { if let t = l.time { Task { await m.provider?.seek(to: t) } } }
                            .id(l.id)
                    }
                    if !synced { Text("Not time-synced").font(.caption).foregroundStyle(.white.opacity(0.4)) }
                    Text("Lyrics: LRCLIB community database").font(.caption2).foregroundStyle(.white.opacity(0.3)).padding(.top, 12)
                }
                .padding(.horizontal, 24).padding(.vertical, 40)
                .animation(.easeInOut(duration: 0.3), value: current)
            }
            .onChange(of: current) { _, c in if let c { withAnimation(.easeInOut(duration: 0.4)) { proxy.scrollTo(c, anchor: .center) } } }
        }
    }

    func load() async {
        result = nil; failed = false
        if demo { result = .lines(Self.demoLines, synced: true); return }
        guard let t = m.state.track else { result = LyricsLoader.Result.none; return }
        if let r = await LyricsLoader.load(t) { result = r } else { failed = true }
    }
}

import SwiftUI
#if canImport(Translation)
import Translation
#endif

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

    static func load(_ t: Track) async -> Result? {
        let key = "\(t.artist)|\(t.title)|\(t.album)"
        if let c = cache[key] { return c }
        guard let r = await fetch(t) else { return nil }   // network error: don't cache, allow retry
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

    /// Handles CRLF, several timestamps on one line (`[00:10.0][00:50.0]text`) and ignores tags like `[ar:Artist]`.
    static func parseLRC(_ s: String) -> [LyricLine] {
        var stamped: [(TimeInterval, String)] = []
        for rawLine in s.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline }) {
            var rest = Substring(rawLine.trimmingCharacters(in: .whitespaces))
            var times: [TimeInterval] = []
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let parts = rest[rest.index(after: rest.startIndex)..<close].split(separator: ":")
                guard parts.count == 2, let mm = Double(parts[0]), let ss = Double(parts[1]) else { break }
                times.append(mm * 60 + ss)
                rest = rest[rest.index(after: close)...]
            }
            let text = rest.trimmingCharacters(in: .whitespaces)
            for t in times { stamped.append((t, text)) }
        }
        return stamped.sorted { $0.0 < $1.0 }.enumerated().map { LyricLine(id: $0.offset, time: $0.element.0, text: $0.element.1) }
    }
}

struct LyricsView: View {
    @ObservedObject var m: PlayerModel
    @Environment(\.dismiss) private var dismiss
    @State private var result: LyricsLoader.Result?
    @State private var failed = false
    enum Mode { case original, romanised, translated }
    @State private var mode = Mode.original
    @State private var translations: [Int: String] = [:]
    @State private var transTrigger = 0
    @State private var transNote: String?
    private var demo: Bool { CommandLine.arguments.contains("-demo") }

    static let demoLines: [LyricLine] = [
        "Demo lyrics for screenshots only", "Not a real song", "Just some sample words", "To show the layout",
        "The current line is bright", "The others stay soft", "Tap a line to jump there",
    ].enumerated().map { LyricLine(id: $0.offset, time: Double($0.offset) * 12, text: $0.element) }

    var body: some View {
        GeometryReader { g in
            let wide = g.size.width > g.size.height
            ZStack {
                // Apple Music look: a soft colour wash taken from the cover.
                LinearGradient(colors: [m.tint.opacity(1), m.tint.opacity(0.55), .black], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay(Color.black.opacity(0.25)).ignoresSafeArea()
                if wide {
                    HStack(spacing: 0) {
                        sideColumn(width: g.size.width * 0.42, height: g.size.height)
                        content.padding(.leading, 40).frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    controls.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    VStack(spacing: 0) { header; content }
                }
            }
        }
        .preferredColorScheme(.dark)
        .task(id: m.state.track?.id) { await load() }
        .modifier(TranslateIfPossible(lines: currentLines, trigger: transTrigger,
                                      done: { translations = $0 }, fail: { transNote = "Translation failed: \($0)" }))
    }

    /// Landscape: big cover, title and artist on the left, lyrics on the right.
    private func sideColumn(width: CGFloat, height: CGFloat) -> some View {
        let side = max(120, min(height * 0.5, width - 120, 300))
        return VStack(alignment: .leading, spacing: 14) {
            Spacer(minLength: 0)
            Group {
                if let a = m.art { Image(uiImage: a).resizable().scaledToFill() } else { Color.white.opacity(0.15) }
            }.frame(width: side, height: side).clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
            VStack(alignment: .leading, spacing: 3) {
                Text(m.state.track?.title ?? "Lyrics").font(.title3.bold()).lineLimit(2)
                Text(m.state.track?.artist ?? "").font(.body).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
            }.frame(width: side, alignment: .leading)
            Spacer(minLength: 0)
        }
        .frame(width: width, alignment: .center)
        .padding(.vertical, 24)
    }

    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark").font(.subheadline.bold()).padding(10).background(.white.opacity(0.18), in: Circle())
        }.foregroundStyle(.white)
    }

    /// Original / romanised / translated. Romanising uses the system's own transliteration (works offline, any iOS).
    /// Translating uses Apple's on-device Translation framework, which needs iOS 18; there is no cloud service and no key.
    private var controls: some View {
        HStack(spacing: 10) {
            if case .lines = result {
                Menu {
                    Button { mode = .original; transNote = nil } label: { Label("Original", systemImage: mode == .original ? "checkmark" : "textformat") }
                    Button { mode = .romanised; transNote = nil } label: { Label("Romanised (Latin letters)", systemImage: mode == .romanised ? "checkmark" : "character") }
                    if translationAvailable {
                        Button { mode = .translated; transNote = nil; if translations.isEmpty { transTrigger += 1 } } label: {
                            Label("Translate to your language", systemImage: mode == .translated ? "checkmark" : "globe")
                        }
                    } else {
                        Text("Translation needs iOS 18")
                    }
                } label: {
                    Image(systemName: "character.bubble").font(.subheadline.bold()).padding(10).background(.white.opacity(0.18), in: Circle())
                }.foregroundStyle(.white).accessibilityLabel("Lyrics language")
            }
            closeButton
        }
    }

    private var translationAvailable: Bool {
        #if canImport(Translation)
        if #available(iOS 18, *) { return true }
        #endif
        return false
    }

    private func shown(_ l: LyricLine) -> String {
        switch mode {
        case .original: return l.text
        case .romanised: return l.text.applyingTransform(.toLatin, reverse: false) ?? l.text
        case .translated: return translations[l.id] ?? l.text
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Group {
                if let a = m.art { Image(uiImage: a).resizable().scaledToFill() } else { Color.white.opacity(0.15) }
            }.frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(m.state.track?.title ?? "Lyrics").font(.headline).lineLimit(1)
                Text(m.state.track?.artist ?? "").font(.subheadline).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
            }
            Spacer()
            controls
        }
        .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 8)
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
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    Spacer().frame(height: 40)
                    ForEach(Array(lines.enumerated()), id: \.element.id) { i, l in
                        let d = current.map { abs(i - $0) } ?? 0
                        let on = !synced || i == current
                        Text(l.text.isEmpty ? "•••" : shown(l))
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(.white.opacity(on ? 1 : (current.map { i < $0 } == true ? 0.3 : 0.45)))
                            .blur(radius: on ? 0 : min(CGFloat(d) * 0.6, 3))
                            .scaleEffect(on ? 1 : 0.93, anchor: .leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture { if let t = l.time { Task { await m.provider?.seek(to: t) } } }
                            .id(l.id)
                    }
                    if mode == .translated, translations.isEmpty { Text(transNote ?? "Translating…").font(.caption).foregroundStyle(.white.opacity(0.5)) }
                    if mode == .romanised { Text("Romanised by the system; may be approximate").font(.caption).foregroundStyle(.white.opacity(0.5)) }
                    if !synced { Text("Not time-synced").font(.caption).foregroundStyle(.white.opacity(0.5)) }
                    Text("Lyrics: LRCLIB community database").font(.caption2).foregroundStyle(.white.opacity(0.4)).padding(.top, 12)
                    Spacer().frame(height: 220)
                }
                .padding(.horizontal, 24)
                .animation(.spring(response: 0.5, dampingFraction: 0.85), value: current)
            }
            .onChange(of: current) { _, c in if let c { withAnimation(.spring(response: 0.6, dampingFraction: 0.9)) { proxy.scrollTo(c, anchor: UnitPoint(x: 0.5, y: 0.3)) } } }
        }
    }

    private var currentLines: [LyricLine] { if case .lines(let l, _) = result { return l }; return [] }

    func load() async {
        result = nil; failed = false; mode = .original; translations = [:]; transNote = nil
        if demo { result = .lines(Self.demoLines, synced: true); return }
        guard let t = m.state.track else { result = LyricsLoader.Result.none; return }
        if let r = await LyricsLoader.load(t) { result = r } else { failed = true }
    }
}

/// Applies the iOS 18 translation task only where the framework exists.
struct TranslateIfPossible: ViewModifier {
    let lines: [LyricLine]; let trigger: Int
    let done: ([Int: String]) -> Void; let fail: (String) -> Void
    func body(content: Content) -> some View {
        #if canImport(Translation)
        if #available(iOS 18, *) { content.modifier(TranslateHost(lines: lines, trigger: trigger, done: done, fail: fail)) }
        else { content }
        #else
        content
        #endif
    }
}

#if canImport(Translation)
@available(iOS 18.0, *)
struct TranslateHost: ViewModifier {
    let lines: [LyricLine]; let trigger: Int
    let done: ([Int: String]) -> Void; let fail: (String) -> Void
    @State private var config: TranslationSession.Configuration?
    func body(content: Content) -> some View {
        content
            .translationTask(config) { session in
                do {
                    let reqs = lines.filter { !$0.text.isEmpty }
                        .map { TranslationSession.Request(sourceText: $0.text, clientIdentifier: String($0.id)) }
                    let res = try await session.translations(from: reqs)
                    var d: [Int: String] = [:]
                    for x in res { if let c = x.clientIdentifier, let i = Int(c) { d[i] = x.targetText } }
                    done(d)
                } catch { fail(error.localizedDescription) }
            }
            .onChange(of: trigger) { _, _ in
                if config == nil { config = .init(source: nil, target: Locale.current.language) } else { config?.invalidate() }
            }
    }
}
#endif

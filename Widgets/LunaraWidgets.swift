import SwiftUI
import WidgetKit
import ActivityKit
import AppIntents

@main struct LunaraWidgetBundle: WidgetBundle {
    var body: some Widget {
        LunaraLiveActivity()
        LunaraRecordWidget()
        LunaraCollectionWidget()
    }
}

struct RecordEntry: TimelineEntry {
    let date: Date
    let snap: WidgetSnapshot?
}

struct RecordProvider: TimelineProvider {
    func placeholder(in context: Context) -> RecordEntry { RecordEntry(date: Date(), snap: nil) }
    func getSnapshot(in context: Context, completion: @escaping (RecordEntry) -> Void) {
        completion(RecordEntry(date: Date(), snap: WidgetSnapshot.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<RecordEntry>) -> Void) {
        completion(Timeline(entries: [RecordEntry(date: Date(), snap: WidgetSnapshot.load())], policy: .never))
    }
}

struct RecordWidgetRoot: View {
    var entry: RecordEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        RecordWidgetView(snap: entry.snap, wide: family != .systemSmall)
            .containerBackground(for: .widget) { Color.black }
    }
}

/// Home-screen widget: the last track Lunara saw. Refreshed whenever the app syncs; it cannot follow playback.
struct LunaraRecordWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LunaraRecord", provider: RecordProvider()) { entry in
            RecordWidgetRoot(entry: entry)
        }
        .configurationDisplayName("Lunara")
        .description("The last record you played in Lunara.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

/// One album picked from the Apple Music (iTunes) catalog. The widget stores only its ID, so it always points at that exact album.
struct AlbumEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Album"
    static var defaultQuery = AlbumQuery()
    var id: String
    var title: String
    var artist: String
    var art: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(artist)", image: URL(string: art).map { DisplayRepresentation.Image(url: $0) })
    }
    init(id: String, title: String, artist: String, art: String) { self.id = id; self.title = title; self.artist = artist; self.art = art }
    init?(_ r: [String: Any]) {
        guard let cid = r["collectionId"] as? Int, let t = r["collectionName"] as? String else { return nil }
        let a = ((r["artworkUrl100"] as? String) ?? "").replacingOccurrences(of: "100x100", with: "400x400")
        self.init(id: String(cid), title: t, artist: (r["artistName"] as? String) ?? "", art: a)
    }
}

struct AlbumQuery: EntityStringQuery {
    private func fetch(_ path: String, _ items: [URLQueryItem]) async -> [AlbumEntity] {
        var c = URLComponents(string: "https://itunes.apple.com/" + path)!
        c.queryItems = items
        guard let u = c.url, let (d, _) = try? await URLSession.shared.data(from: u),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let rs = j["results"] as? [[String: Any]] else { return [] }
        return rs.filter { ($0["wrapperType"] as? String) == "collection" }.compactMap { AlbumEntity($0) }
    }
    func entities(for identifiers: [String]) async throws -> [AlbumEntity] {
        let got = await fetch("lookup", [.init(name: "id", value: identifiers.joined(separator: ","))])
        return identifiers.compactMap { id in got.first { $0.id == id } }
    }
    func entities(matching string: String) async throws -> [AlbumEntity] {
        await fetch("search", [.init(name: "term", value: string), .init(name: "media", value: "music"),
                               .init(name: "entity", value: "album"), .init(name: "limit", value: "25")])
    }
    func suggestedEntities() async throws -> [AlbumEntity] {
        [] // the picker starts empty; the user searches by album or artist name
    }
}

struct CollectionIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Collection"
    static var description = IntentDescription("Search and pick up to 6 albums.")
    @Parameter(title: "Album 1") var a1: AlbumEntity?
    @Parameter(title: "Album 2") var a2: AlbumEntity?
    @Parameter(title: "Album 3") var a3: AlbumEntity?
    @Parameter(title: "Album 4") var a4: AlbumEntity?
    @Parameter(title: "Album 5") var a5: AlbumEntity?
    @Parameter(title: "Album 6") var a6: AlbumEntity?
    var albums: [AlbumEntity] { [a1, a2, a3, a4, a5, a6].compactMap { $0 } }
}

struct CollectionEntry: TimelineEntry { let date: Date; let items: [CollectionCard] }

/// Downloads the covers of the picked albums from the widget itself, so nothing has to be shared with the app.
enum AlbumLookup {
    static func cards(_ albums: [AlbumEntity]) async -> [CollectionCard] {
        await withTaskGroup(of: (Int, CollectionCard).self) { g in
            for (i, a) in albums.enumerated() {
                g.addTask {
                    var img: UIImage?
                    if let u = URL(string: a.art), let (d, _) = try? await URLSession.shared.data(from: u) { img = UIImage(data: d) }
                    return (i, CollectionCard(id: a.id, title: a.title, artist: a.artist, image: img))
                }
            }
            var out: [(Int, CollectionCard)] = []
            for await r in g { out.append(r) }
            return out.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
    }
}

struct CollectionProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> CollectionEntry { CollectionEntry(date: Date(), items: []) }
    func snapshot(for configuration: CollectionIntent, in context: Context) async -> CollectionEntry {
        CollectionEntry(date: Date(), items: await AlbumLookup.cards(Array(configuration.albums.prefix(3))))
    }
    func timeline(for configuration: CollectionIntent, in context: Context) async -> Timeline<CollectionEntry> {
        let n = context.family == .systemSmall ? 1 : context.family == .systemMedium ? 3 : 6
        let e = CollectionEntry(date: Date(), items: await AlbumLookup.cards(Array(configuration.albums.prefix(n))))
        return Timeline(entries: [e], policy: .after(Date().addingTimeInterval(6 * 3600)))
    }
}

struct CollectionWidgetRoot: View {
    var entry: CollectionEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        CollectionWidgetView(items: entry.items, family: family == .systemSmall ? .small : family == .systemMedium ? .medium : .large)
            .containerBackground(for: .widget) { Color.black }
    }
}

/// Albums typed in the widget's own settings; covers come from the Apple Music search API. No App Group needed.
struct LunaraCollectionWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "LunaraCollection", intent: CollectionIntent.self, provider: CollectionProvider()) { CollectionWidgetRoot(entry: $0) }
            .configurationDisplayName("Lunara collection")
            .description("A shelf of albums you type in. Touch and hold, then Edit Widget.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct LunaraLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LunaraActivityAttributes.self) { ctx in
            NowPlayingCard(s: ctx.state)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { ctx in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { RecordGlyph(tint: ctx.state.tint).frame(width: 44, height: 44) }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(ctx.state.title).font(.headline).lineLimit(1)
                        Text(ctx.state.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) { ActivityProgress(s: ctx.state) }
            } compactLeading: {
                RecordGlyph(tint: ctx.state.tint).frame(width: 20, height: 20)
            } compactTrailing: {
                Image(systemName: ctx.state.isPlaying ? "waveform" : "pause.fill")
            } minimal: {
                RecordGlyph(tint: ctx.state.tint).frame(width: 20, height: 20)
            }
        }
    }
}

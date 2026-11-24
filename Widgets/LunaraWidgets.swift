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

struct CollectionIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Collection"
    static var description = IntentDescription("Type up to 6 albums, for example \"Daft Punk Discovery\".")
    @Parameter(title: "Album 1") var a1: String?
    @Parameter(title: "Album 2") var a2: String?
    @Parameter(title: "Album 3") var a3: String?
    @Parameter(title: "Album 4") var a4: String?
    @Parameter(title: "Album 5") var a5: String?
    @Parameter(title: "Album 6") var a6: String?
    var queries: [String] { [a1, a2, a3, a4, a5, a6].compactMap { $0?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
}

struct CollectionEntry: TimelineEntry { let date: Date; let items: [CollectionCard] }

/// Looks each album up on the Apple Music (iTunes) Search API from the widget itself, so nothing has to be shared with the app.
enum AlbumLookup {
    static func card(_ q: String) async -> CollectionCard? {
        var c = URLComponents(string: "https://itunes.apple.com/search")!
        c.queryItems = [.init(name: "term", value: q), .init(name: "entity", value: "album"), .init(name: "limit", value: "1")]
        guard let u = c.url, let (d, _) = try? await URLSession.shared.data(from: u),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let r = (j["results"] as? [[String: Any]])?.first,
              let title = r["collectionName"] as? String else { return nil }
        var img: UIImage?
        if let s = (r["artworkUrl100"] as? String)?.replacingOccurrences(of: "100x100", with: "400x400"), let iu = URL(string: s),
           let (id, _) = try? await URLSession.shared.data(from: iu) { img = UIImage(data: id) }
        return CollectionCard(id: q, title: title, artist: (r["artistName"] as? String) ?? "", image: img)
    }
    static func cards(_ qs: [String]) async -> [CollectionCard] {
        await withTaskGroup(of: (Int, CollectionCard?).self) { g in
            for (i, q) in qs.enumerated() { g.addTask { (i, await card(q)) } }
            var out: [(Int, CollectionCard)] = []
            for await (i, c) in g { if let c { out.append((i, c)) } }
            return out.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
    }
}

struct CollectionProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> CollectionEntry { CollectionEntry(date: Date(), items: []) }
    func snapshot(for configuration: CollectionIntent, in context: Context) async -> CollectionEntry {
        CollectionEntry(date: Date(), items: await AlbumLookup.cards(Array(configuration.queries.prefix(3))))
    }
    func timeline(for configuration: CollectionIntent, in context: Context) async -> Timeline<CollectionEntry> {
        let n = context.family == .systemSmall ? 1 : context.family == .systemMedium ? 3 : 6
        let e = CollectionEntry(date: Date(), items: await AlbumLookup.cards(Array(configuration.queries.prefix(n))))
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

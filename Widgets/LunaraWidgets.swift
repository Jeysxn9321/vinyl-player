import SwiftUI
import WidgetKit
import ActivityKit

@main struct LunaraWidgetBundle: WidgetBundle {
    var body: some Widget {
        LunaraLiveActivity()
        LunaraRecordWidget()
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

import SwiftUI
import WidgetKit
import ActivityKit

@main struct LunaraWidgetBundle: WidgetBundle {
    var body: some Widget { LunaraLiveActivity() }
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

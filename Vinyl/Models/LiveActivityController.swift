import SwiftUI
import ActivityKit
import WidgetKit

/// Starts, updates and ends the lock-screen Live Activity. The app is suspended in the background (no audio,
/// no push), so the card cannot follow track changes while locked: the progress bar runs from a timer and the
/// activity goes stale at the track's end.
@MainActor enum LiveActivityController {
    private static var current: Activity<LunaraActivityAttributes>?

    static func sync(_ s: MusicState, tint: Color) {
        var r: CGFloat = 0.1, g: CGFloat = 0.1, b: CGFloat = 0.1, a: CGFloat = 0
        UIColor(tint).getRed(&r, green: &g, blue: &b, alpha: &a)
        // Home-screen widget: remember the last track (kept when playback stops). Needs the App Group to work.
        if let t = s.track {
            WidgetSnapshot.save(WidgetSnapshot(title: t.title, artist: t.artist, isPlaying: s.isPlaying,
                tintR: Double(min(1, r * 3.5)), tintG: Double(min(1, g * 3.5)), tintB: Double(min(1, b * 3.5))))
            WidgetCenter.shared.reloadAllTimelines()
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard let t = s.track else { end(); return }
        let start = Date().addingTimeInterval(-s.progress)
        let end = t.duration > 0 ? start.addingTimeInterval(t.duration) : nil
        let state = LunaraActivityAttributes.ContentState(
            title: t.title, artist: t.artist, isPlaying: s.isPlaying,
            start: s.isPlaying ? start : nil, end: end,
            progress: t.duration > 0 ? s.progress / t.duration : 0,
            tintR: Double(min(1, r * 3.5)), tintG: Double(min(1, g * 3.5)), tintB: Double(min(1, b * 3.5)))
        let content = ActivityContent(state: state, staleDate: end)
        if let act = current ?? Activity<LunaraActivityAttributes>.activities.first {
            current = act
            Task { await act.update(content) }
        } else {
            let provider = s.provider == .appleMusic ? "Apple Music" : "Spotify"
            current = try? Activity.request(attributes: LunaraActivityAttributes(provider: provider), content: content)
        }
    }

    static func end() {
        let act = current ?? Activity<LunaraActivityAttributes>.activities.first
        current = nil
        guard let act else { return }
        Task { await act.end(nil, dismissalPolicy: .immediate) }
    }
}

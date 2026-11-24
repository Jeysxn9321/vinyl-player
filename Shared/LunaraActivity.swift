import SwiftUI
import ActivityKit

/// Live Activity payload. Kept small: no artwork bytes, only text, timing and the record tint.
struct LunaraActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var artist: String
        var isPlaying: Bool
        var start: Date?      // when playing: now - progress, so the timer counts without app updates
        var end: Date?        // start + duration
        var progress: Double  // 0...1, used while paused
        var tintR: Double
        var tintG: Double
        var tintB: Double
        var tint: Color { Color(red: tintR, green: tintG, blue: tintB) }
    }
    var provider: String
}

/// Small flat record used in the lock-screen card and the Dynamic Island (activities cannot animate).
struct RecordGlyph: View {
    var tint: Color
    var body: some View {
        GeometryReader { g in
            let s = min(g.size.width, g.size.height)
            ZStack {
                Circle().fill(Color(white: 0.06))
                Circle().inset(by: s * 0.12).stroke(Color.white.opacity(0.08), lineWidth: 0.7)
                Circle().inset(by: s * 0.2).stroke(Color.white.opacity(0.06), lineWidth: 0.7)
                Circle().fill(tint.opacity(0.9)).frame(width: s * 0.36, height: s * 0.36)
                Circle().fill(.black).frame(width: s * 0.06, height: s * 0.06)
            }.frame(width: s, height: s)
        }.aspectRatio(1, contentMode: .fit)
    }
}

struct ActivityProgress: View {
    var s: LunaraActivityAttributes.ContentState
    var body: some View {
        if s.isPlaying, let a = s.start, let b = s.end, a < b {
            ProgressView(timerInterval: a...b, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                .tint(.white)
        } else {
            ProgressView(value: min(max(s.progress, 0), 1)).tint(.white)
        }
    }
}

/// Lock-screen card. The app can also render it under `-card` for a CI screenshot.
struct NowPlayingCard: View {
    var s: LunaraActivityAttributes.ContentState
    var body: some View {
        HStack(spacing: 14) {
            RecordGlyph(tint: s.tint).frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(s.title).font(.headline).lineLimit(1)
                Text(s.artist).font(.subheadline).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
                ActivityProgress(s: s).padding(.top, 4)
            }
            Spacer(minLength: 0)
            Image(systemName: s.isPlaying ? "waveform" : "pause.fill").font(.title3).foregroundStyle(.white.opacity(0.8))
        }
        .foregroundStyle(.white)
        .padding(16)
    }
}

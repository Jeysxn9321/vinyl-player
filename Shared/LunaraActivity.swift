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
                Circle().stroke(tint.opacity(0.55), lineWidth: max(1, s * 0.03))
                Circle().inset(by: s * 0.06).stroke(Color.white.opacity(0.07), lineWidth: 0.7)
                Circle().inset(by: s * 0.12).stroke(Color.white.opacity(0.08), lineWidth: 0.7)
                Circle().inset(by: s * 0.2).stroke(Color.white.opacity(0.06), lineWidth: 0.7)
                Circle().fill(tint.opacity(0.9)).frame(width: s * 0.36, height: s * 0.36)
                Circle().fill(.black).frame(width: s * 0.06, height: s * 0.06)
            }.frame(width: s, height: s)
        }.aspectRatio(1, contentMode: .fit)
    }
}

/// Progress bar in the record's tint. While playing it runs from a timer, so the app need not update it.
struct ActivityProgress: View {
    var s: LunaraActivityAttributes.ContentState
    var body: some View {
        if s.isPlaying, let a = s.start, let b = s.end, a < b {
            ProgressView(timerInterval: a...b, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                .tint(s.tint)
        } else {
            ProgressView(value: min(max(s.progress, 0), 1)).tint(s.tint)
        }
    }
}

/// Small flat tonearm drawn over the record (static: activities cannot animate).
struct ToneArm: View {
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: w * 0.78, y: h * 0.12))
                    p.addLine(to: CGPoint(x: w * 0.78, y: h * 0.55))
                    p.addLine(to: CGPoint(x: w * 0.66, y: h * 0.8))
                }.stroke(Color(white: 0.75), style: StrokeStyle(lineWidth: max(1.5, w * 0.03), lineCap: .round, lineJoin: .round))
                Circle().fill(Color(white: 0.8)).frame(width: w * 0.2, height: w * 0.2).position(x: w * 0.78, y: h * 0.12)
                Circle().fill(.black).frame(width: w * 0.06, height: w * 0.06).position(x: w * 0.78, y: h * 0.12)
            }
        }
    }
}

/// Lock-screen card, styled after the in-app player: record with tonearm, big title, tinted artist and bar.
/// The app can also render it under `-card` for a CI screenshot.
struct NowPlayingCard: View {
    var s: LunaraActivityAttributes.ContentState
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RecordGlyph(tint: s.tint).frame(width: 84, height: 84).padding(.trailing, 8)
                ToneArm().frame(width: 92, height: 92)
            }.frame(width: 92, height: 92)
            VStack(alignment: .leading, spacing: 3) {
                Text(s.title).font(.title3.weight(.bold)).lineLimit(1)
                Text(s.artist).font(.subheadline).foregroundStyle(s.tint.opacity(0.95)).lineLimit(1)
                ActivityProgress(s: s).padding(.top, 8)
                HStack {
                    if s.isPlaying, let a = s.start { Text(a, style: .timer).monospacedDigit() }
                    else { Text(s.isPlaying ? "" : "Paused") }
                    Spacer()
                    Image(systemName: s.isPlaying ? "waveform" : "pause.fill")
                }.font(.caption2).foregroundStyle(.white.opacity(0.55))
            }
        }
        .foregroundStyle(.white)
        .padding(16)
    }
}

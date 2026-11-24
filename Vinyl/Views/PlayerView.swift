import SwiftUI

@MainActor final class PlayerModel: ObservableObject {
    @Published var state = MusicState()
    @Published var art: UIImage?
    @Published var error: String?
    @Published var provider: MusicProvider?

    private func apply(_ s: MusicState) {
        let changed = s.track?.id != state.track?.id
        state = s
        if changed, let u = s.track?.artworkURL {
            Task {
                if let (d, _) = try? await URLSession.shared.data(from: u), let i = UIImage(data: d) {
                    withAnimation(.easeInOut(duration: 0.6)) { art = i }
                }
            }
        }
    }

    /// Launch with `-demo` to render the player with sample data (visual QA only).
    func loadDemo() {
        state = MusicState(track: Track(id: "demo", title: "Family Matters", artist: "Demo Artist", album: "Demo",
                                        artworkURL: nil, duration: 240), isPlaying: true, progress: 83)
        art = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 600)).image { c in
            let cg = c.cgContext
            let g = CGGradient(colorsSpace: nil, colors: [UIColor.systemOrange.cgColor, UIColor.brown.cgColor] as CFArray, locations: [0, 1])!
            cg.drawLinearGradient(g, start: .zero, end: CGPoint(x: 600, y: 600), options: [])
        }
    }

    func connect(_ p: MusicProvider) async {
        p.onState = { [weak self] s in Task { @MainActor in self?.apply(s) } }
        do { try await p.authorize(); provider = p; error = nil }
        catch { self.error = error.localizedDescription }
    }
}

struct PlayerView: View {
    @ObservedObject var m: PlayerModel

    var body: some View {
        GeometryReader { g in
            let wide = g.size.width > g.size.height
            let side = wide ? min(g.size.width * 0.58 / 2.0, g.size.height * 0.7) : min(g.size.width * 0.9 / 2.0, g.size.height * 0.4)
            ZStack {
                if wide {
                    HStack(spacing: 24) {
                        composition(side)
                        VStack(spacing: 20) { info; controls }.frame(maxWidth: .infinity)
                    }.padding(.horizontal, 24)
                } else {
                    VStack(spacing: 44) {
                        Spacer(minLength: 0)
                        composition(side)
                        info
                        controls
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(width: g.size.width, height: g.size.height)
        }
        .background {
            ZStack {
                Color.black
                if let a = m.art {
                    Image(uiImage: a).resizable().scaledToFill().blur(radius: 80).opacity(0.35)
                }
            }.ignoresSafeArea()
        }
    }


    func composition(_ side: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            SpinningDisc(playing: m.state.isPlaying, color: Color(white: 0.06), label: m.art)
                            .frame(width: side, height: side)
                            .offset(x: m.state.isPlaying ? side * 0.82 : side * 0.45)
                            .animation(.spring(response: 0.9, dampingFraction: 0.85), value: m.state.isPlaying)
                        Group {
                            if let a = m.art { Image(uiImage: a).resizable().scaledToFill() } else { Color(white: 0.15) }
                        }
                        .frame(width: side, height: side).clipped()
                        .shadow(color: .black.opacity(0.7), radius: 24, y: 14)
                        Tonearm(playing: m.state.isPlaying, length: side * 0.95)
                            .offset(x: side * 1.6, y: side * 0.02)
        }
        .frame(width: side * 2.0, height: side, alignment: .topLeading)
        .accessibilityHidden(true)
    }
    var info: some View {
        VStack(spacing: 14) {
        VStack(spacing: 4) {
                        Text(m.state.track?.title ?? "Nothing playing").font(.title3.bold())
                        Text(m.state.track?.artist ?? "").font(.subheadline).foregroundStyle(.white.opacity(0.65))
                    }
                    .foregroundStyle(.white)

                    if let t = m.state.track, t.duration > 0 {
                        ProgressView(value: min(m.state.progress, t.duration), total: t.duration)
                            .tint(.white).padding(.horizontal, 40)
                        HStack { Text(fmt(m.state.progress)); Spacer(); Text(fmt(t.duration)) }
                            .font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.65)).padding(.horizontal, 40)
                    }
        }
    }
    var controls: some View {
        VStack(spacing: 18) {
                    HStack(spacing: 44) {
                        btn("backward.fill", "Previous") { await m.provider?.previous() }
                        btn(m.state.isPlaying ? "pause.circle.fill" : "play.circle.fill",
                            m.state.isPlaying ? "Pause" : "Play", big: true) {
                            if m.state.isPlaying { await m.provider?.pause() } else { await m.provider?.play() }
                        }
                        btn("forward.fill", "Next") { await m.provider?.next() }
                    }
        }
    }

    func fmt(_ t: TimeInterval) -> String { String(format: "%d:%02d", Int(t) / 60, Int(t) % 60) }

    func btn(_ icon: String, _ label: String, big: Bool = false, _ a: @escaping () async -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            Task { await a() }
        } label: {
            Image(systemName: icon).font(.system(size: big ? 52 : 26)).foregroundStyle(.white)
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel(label)
    }
}

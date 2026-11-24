import SwiftUI

@MainActor final class PlayerModel: ObservableObject {
    @Published var state = MusicState()
    @Published var art: UIImage?
    @Published var tint: Color = Color(white: 0.06)
    @Published var error: String?
    @Published var provider: MusicProvider?

    private func apply(_ s: MusicState) {
        let changed = s.track?.id != state.track?.id
        state = s
        if changed, let u = s.track?.artworkURL {
            Task {
                if let (d, _) = try? await URLSession.shared.data(from: u), let i = UIImage(data: d) {
                    withAnimation(.easeInOut(duration: 0.6)) { art = i; tint = (UserDefaults.standard.object(forKey: Pref.tint) as? Bool ?? true) ? Self.discTint(i) : Color(white: 0.06) }
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
        if let a = art { tint = Self.discTint(a) }
    }

    /// Average colour of the artwork, darkened so the record stays a record.
    static func discTint(_ i: UIImage) -> Color {
        var px = [UInt8](repeating: 0, count: 4)
        guard let cg = i.cgImage, let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return Color(white: 0.06) }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return Color(red: Double(px[0]) / 255 * 0.22, green: Double(px[1]) / 255 * 0.22, blue: Double(px[2]) / 255 * 0.22)
    }

    func connect(_ p: MusicProvider) async {
        p.onState = { [weak self] s in Task { @MainActor in self?.apply(s) } }
        do {
            try await p.authorize(); provider = p; error = nil
            UserDefaults.standard.set(p.kind.rawValue, forKey: Pref.lastProvider)
        } catch { self.error = error.localizedDescription }
    }

    func disconnect() {
        provider?.disconnect(); provider = nil; art = nil; state = MusicState()
        UserDefaults.standard.removeObject(forKey: Pref.lastProvider)
    }

    /// Silent reconnect on launch. Falls back to onboarding if it fails.
    func restore() async {
        guard provider == nil, let raw = UserDefaults.standard.string(forKey: Pref.lastProvider),
              let kind = ProviderKind(rawValue: raw) else { return }
        let p: MusicProvider = kind == .spotify ? SpotifyProvider() : AppleMusicProvider()
        p.onState = { [weak self] s in Task { @MainActor in self?.apply(s) } }
        do {
            if let sp = p as? SpotifyProvider { try await sp.restore() } else { try await p.authorize() }
            provider = p
        } catch { UserDefaults.standard.removeObject(forKey: Pref.lastProvider) }
    }
}

struct PlayerView: View {
    @ObservedObject var m: PlayerModel
    @State private var showControls = CommandLine.arguments.contains("-demo") && !CommandLine.arguments.contains("-hidden")
    @State private var hideTask: Task<Void, Never>?
    @State private var showSettings = false
    @AppStorage(Pref.autoHide) private var autoHide = true

    var body: some View {
        GeometryReader { g in
            let lm = LayoutMetrics(size: g.size)
            let wide = lm.shape != .portrait
            let side = lm.recordSide
            ZStack {
                if wide {
                    HStack(spacing: 24) {
                        composition(side)
                        VStack(spacing: 20) { info(lm.showsProgress); controls }.frame(maxWidth: .infinity)
                    }.padding(.horizontal, 24)
                } else {
                    VStack(spacing: 44) {
                        Spacer(minLength: 0)
                        composition(side)
                        info(lm.showsProgress)
                        controls
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(width: g.size.width, height: g.size.height)
        }
        .overlay(alignment: .top) { pill }
        .contentShape(Rectangle())
        .onTapGesture { reveal() }
        .sheet(isPresented: $showSettings) { SettingsView(m: m) }
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
            SpinningDisc(playing: m.state.isPlaying, color: m.tint, label: m.art, title: m.state.track?.title ?? "")
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
    func info(_ progress: Bool) -> some View {
        VStack(spacing: 14) {
        VStack(spacing: 4) {
                        Text(m.state.track?.title ?? "Nothing playing").font(.title3.bold())
                        Text(m.state.track?.artist ?? "").font(.subheadline).foregroundStyle(.white.opacity(0.65))
                    }
                    .foregroundStyle(.white)

                    if progress, let t = m.state.track, t.duration > 0 {
                        ProgressView(value: min(m.state.progress, t.duration), total: t.duration)
                            .tint(.white).padding(.horizontal, 40)
                        HStack { Text(fmt(m.state.progress)); Spacer(); Text(fmt(t.duration)) }
                            .font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.65)).padding(.horizontal, 40)
                    }
        }
    }
    @ViewBuilder var pill: some View {
        if m.state.track == nil, let p = m.provider {
            Text(p.kind == .spotify ? "Connecting to Spotify" : "Connecting to Apple Music")
                .font(.footnote.weight(.medium)).foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(.ultraThinMaterial, in: Capsule()).padding(.top, 8)
        }
    }

    /// Controls fade out like the reference video; a tap brings them back for a few seconds.
    func reveal() {
        withAnimation(.easeOut(duration: 0.25)) { showControls = true }
        hideTask?.cancel()
        guard autoHide else { return }
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled { withAnimation(.easeIn(duration: 0.5)) { showControls = false } }
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
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape").font(.system(size: 20)).foregroundStyle(.white.opacity(0.7)).frame(minWidth: 44, minHeight: 44)
                    }.accessibilityLabel("Settings")
        }
        .opacity(showControls ? 1 : 0)
        .allowsHitTesting(showControls)
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

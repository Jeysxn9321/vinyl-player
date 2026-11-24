import SwiftUI

@MainActor final class PlayerModel: ObservableObject {
    @Published var state = MusicState()
    @Published var art: UIImage?
    @Published var tint: Color = Color(white: 0.06)
    @Published var error: String?
    @Published var provider: MusicProvider?

    private var artTask: Task<Void, Never>?
    private var busy = false   // a connect or restore is running

    private func apply(_ s: MusicState) {
        let changed = s.track?.id != state.track?.id
        let playChanged = s.isPlaying != state.isPlaying
        state = s
        if changed || playChanged { LiveActivityController.sync(s, tint: tint) }
        guard changed else { return }
        artTask?.cancel()
        guard let u = s.track?.artworkURL else {
            // No artwork for this item (local file, episode): don't keep the previous cover.
            if s.track != nil || art != nil { withAnimation(.easeInOut(duration: 0.6)) { art = nil; tint = Color(white: 0.06) } }
            return
        }
        let id = s.track?.id
        artTask = Task {
            guard let (d, _) = try? await URLSession.shared.data(from: u), let i = UIImage(data: d),
                  !Task.isCancelled, state.track?.id == id else { return }
            withAnimation(.easeInOut(duration: 0.6)) { art = i; tint = (UserDefaults.standard.object(forKey: Pref.tint) as? Bool ?? true) ? Self.discTint(i) : Color(white: 0.06) }
            LiveActivityController.sync(state, tint: tint)
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
        guard !busy else { return }   // ignore double taps and taps while a restore runs
        busy = true; defer { busy = false }
        p.onState = { [weak self] s in Task { @MainActor in if let self, self.busy || self.provider != nil { self.apply(s) } } }
        do {
            try await p.authorize(); provider = p; error = nil
            UserDefaults.standard.set(p.kind.rawValue, forKey: Pref.lastProvider)
        } catch { self.error = error.localizedDescription }
    }

    /// Called when the tint setting flips so it applies to the current record immediately.
    func retint() {
        let on = UserDefaults.standard.object(forKey: Pref.tint) as? Bool ?? true
        withAnimation(.easeInOut(duration: 0.4)) { tint = (on && art != nil) ? Self.discTint(art!) : Color(white: 0.06) }
    }

    var spotify: SpotifyProvider? { provider as? SpotifyProvider }
    var appleMusic: AppleMusicProvider? { provider as? AppleMusicProvider }

    /// Signs in again on the same provider (needed when the saved token lacks the playlist scopes).
    /// A cancel or failure leaves the existing login untouched.
    func reauthorizeSpotify() async -> Bool {
        guard let sp = spotify else { return false }
        return (try? await sp.authorize()) != nil
    }

    func disconnect() {
        provider?.onState = nil
        LiveActivityController.end()
        provider?.disconnect(); provider = nil; artTask?.cancel(); art = nil; tint = Color(white: 0.06); state = MusicState()
        UserDefaults.standard.removeObject(forKey: Pref.lastProvider)
    }

    /// Silent reconnect on launch. Falls back to onboarding if it fails.
    func restore() async {
        guard !busy, provider == nil, let raw = UserDefaults.standard.string(forKey: Pref.lastProvider),
              let kind = ProviderKind(rawValue: raw) else { return }
        busy = true; defer { busy = false }
        let p: MusicProvider = kind == .spotify ? SpotifyProvider() : AppleMusicProvider()
        p.onState = { [weak self] s in Task { @MainActor in if let self, self.busy || self.provider != nil { self.apply(s) } } }
        do {
            if let sp = p as? SpotifyProvider { try await sp.restore() } else { try await p.authorize() }
            provider = p
        } catch {
            // Only forget the provider when access was really refused, not when offline or on a server error.
            if error is MusicError { UserDefaults.standard.removeObject(forKey: Pref.lastProvider) }
        }
    }
}

struct PlayerView: View {
    @ObservedObject var m: PlayerModel
    @State private var showControls = !CommandLine.arguments.contains("-hidden")
    @State private var hideTask: Task<Void, Never>?
    @State private var showBrowser = CommandLine.arguments.contains("-browser")
    @State private var showQueue = CommandLine.arguments.contains("-queue")
    @State private var showAM = CommandLine.arguments.contains("-ambrowser")
    @State private var showSettings = CommandLine.arguments.contains("-settings")
    @AppStorage(Pref.autoHide) private var autoHide = true
    @AppStorage(Pref.vinylColor) private var vinylColor = VinylColor.auto.rawValue
    @AppStorage(Pref.theme) private var theme = AppTheme.auto.rawValue
    private var discColor: Color { VinylColor(rawValue: vinylColor)?.color ?? m.tint }

    var body: some View {
        GeometryReader { g in
            let lm = LayoutMetrics(size: g.size)
            let wide = lm.shape != .portrait
            let side = lm.recordSide
            if wide {
                HStack(spacing: 24) {
                    composition(side)
                    VStack(spacing: 20) { info(lm.showsProgress); controls }.frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 24)
                .frame(width: g.size.width, height: g.size.height)
            } else {
                portrait(g.size)
            }
        }
        .overlay(alignment: .top) { pill }
        .contentShape(Rectangle())
        .onTapGesture { reveal() }
        .onAppear { if !CommandLine.arguments.contains("-demo") { reveal() } }
        .onChange(of: autoHide) { _, on in if on { reveal() } else { hideTask?.cancel(); showControls = true } }
        .sheet(isPresented: $showSettings) { SettingsView(m: m) }
        .sheet(isPresented: $showBrowser) { PlaylistsView(m: m) }
        .sheet(isPresented: $showQueue) { QueueView(m: m) }
        .sheet(isPresented: $showAM) { AppleMusicLibraryView(m: m) }
        .background {
            ZStack {
                Color.black
                if let cs = (AppTheme(rawValue: theme) ?? .auto).colors {
                    LinearGradient(colors: cs, startPoint: .top, endPoint: .bottom)
                } else if let a = m.art {
                    Image(uiImage: a).resizable().scaledToFill().blur(radius: 80).opacity(0.35)
                }
            }.ignoresSafeArea()
        }
    }


    /// Full-screen record: disc fills the width with the real cover as its label, tonearm at the right edge,
    /// title bottom-left, controls underneath.
    func portrait(_ size: CGSize) -> some View {
        let d = min(size.width * 1.02, size.height * 0.58)
        return ZStack(alignment: .topLeading) {
            Circle().stroke(tintLight.opacity(0.85), lineWidth: 2)
                .frame(width: d, height: d).blur(radius: 1.5)
                .shadow(color: tintLight.opacity(0.7), radius: 26)
                .offset(x: (size.width - d) / 2, y: size.height * 0.07)
            SpinningDisc(playing: m.state.isPlaying, color: discColor, label: m.art, title: m.state.track?.title ?? "", labelScale: 0.44, inlineTitle: false)
                .frame(width: d, height: d)
                .offset(x: (size.width - d) / 2, y: size.height * 0.07)
            Tonearm(playing: m.state.isPlaying, length: d * 0.5, playAngle: 10, onSet: setPlaying)
                .offset(x: size.width - d * 0.22, y: size.height * 0.05)
            VStack(alignment: .leading, spacing: 4) {
                Spacer()
                Text(m.state.track?.title ?? "Nothing playing").font(.title2.bold()).lineLimit(2)
                Text(m.state.track?.artist ?? "").font(.subheadline).foregroundStyle(tintLight).lineLimit(1)
                if let t = m.state.track, t.duration > 0 {
                    GlowProgress(value: min(m.state.progress, t.duration), total: t.duration, tint: tintLight).padding(.top, 14)
                    HStack { Text(fmt(m.state.progress)); Spacer(); Text("-" + fmt(max(0, t.duration - m.state.progress))) }
                        .font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.6))
                }
                HStack(spacing: 22) {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred(); reveal()
                        Task { await m.provider?.setShuffle(!m.state.shuffle) }
                    } label: { modeIcon("shuffle", on: m.state.shuffle) }.accessibilityLabel("Shuffle")
                    Spacer()
                    btn("backward.fill", "Previous") { await m.provider?.previous() }
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred(); reveal()
                        Task { if m.state.isPlaying { await m.provider?.pause() } else { await m.provider?.play() } }
                    } label: {
                        Image(systemName: m.state.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 30)).foregroundStyle(tintLight)
                            .frame(width: 78, height: 78)
                            .background(Circle().fill(Color.black.opacity(0.35)))
                            .overlay(Circle().stroke(tintLight.opacity(0.9), lineWidth: 2))
                            .shadow(color: tintLight.opacity(0.6), radius: 14)
                    }.accessibilityLabel(m.state.isPlaying ? "Pause" : "Play")
                    btn("forward.fill", "Next") { await m.provider?.next() }
                    Spacer()
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred(); reveal()
                        Task { await m.provider?.setRepeat(m.state.repeatMode.next) }
                    } label: { modeIcon(m.state.repeatMode == .one ? "repeat.1" : "repeat", on: m.state.repeatMode != .off) }
                        .accessibilityLabel("Repeat")
                }
                .opacity(showControls ? 1 : 0).allowsHitTesting(showControls).padding(.top, 8)
                utilityRow.padding(.top, 2)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 24).padding(.bottom, 20)
            .frame(width: size.width, height: size.height, alignment: .bottomLeading)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    /// Tonearm drag result: arm on the record plays, arm lifted pauses.
    func setPlaying(_ on: Bool) {
        if CommandLine.arguments.contains("-demo") { return }
        Task { if on { await m.provider?.play() } else { await m.provider?.pause() } }
    }

    func composition(_ side: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            SpinningDisc(playing: m.state.isPlaying, color: discColor, label: m.art, title: m.state.track?.title ?? "")
                            .frame(width: side, height: side)
                            .offset(x: m.state.isPlaying ? side * 0.82 : side * 0.45)
                            .animation(.spring(response: 0.9, dampingFraction: 0.85), value: m.state.isPlaying)
                        Group {
                            if let a = m.art { Image(uiImage: a).resizable().scaledToFill() } else { Color(white: 0.15) }
                        }
                        .frame(width: side, height: side).clipped()
                        .shadow(color: .black.opacity(0.7), radius: 24, y: 14)
                        Tonearm(playing: m.state.isPlaying, length: side * 0.95, onSet: setPlaying)
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
        if m.state.track == nil, m.provider != nil || m.state.provider != nil {
            Text(pillText)
                .font(.footnote.weight(.medium)).foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(.ultraThinMaterial, in: Capsule()).padding(.top, 8)
        }
    }

    var pillText: String {
        let spotify = (m.provider?.kind ?? m.state.provider) == .spotify
        let name = spotify ? "Spotify" : "Apple Music"
        // state.provider is only set once the provider has actually answered.
        return m.state.provider == nil ? "Connecting to \(name)" : (spotify ? "Nothing playing. Press play in Spotify" : "Apple Music connected. Pick something from the library button")
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

    /// Library / queue / playlists / settings icons.
    var utilityRow: some View {
        HStack(spacing: 28) {
            Spacer()
            if m.appleMusic != nil || CommandLine.arguments.contains("-ambrowser") {
                Button { showAM = true } label: { utilIcon("square.stack") }.accessibilityLabel("Library")
            }
            if m.spotify != nil || (CommandLine.arguments.contains("-demo") && !CommandLine.arguments.contains("-ambrowser")) {
                Button { showQueue = true } label: { utilIcon("list.bullet") }.accessibilityLabel("Queue")
                Button { showBrowser = true } label: { utilIcon("square.stack") }.accessibilityLabel("Playlists")
            }
            Button { showSettings = true } label: { utilIcon("gearshape") }.accessibilityLabel("Settings")
            Spacer()
        }
        .opacity(showControls ? 1 : 0).allowsHitTesting(showControls)
    }
    func modeIcon(_ n: String, on: Bool) -> some View {
        Image(systemName: n).font(.system(size: 20, weight: .semibold))
            .foregroundStyle(on ? tintLight : .white.opacity(0.55))
            .shadow(color: on ? tintLight.opacity(0.7) : .clear, radius: 6)
            .frame(minWidth: 44, minHeight: 44)
    }
    func utilIcon(_ n: String) -> some View {
        Image(systemName: n).font(.system(size: 20)).foregroundStyle(.white.opacity(0.7)).frame(minWidth: 44, minHeight: 44)
    }
    /// Lightened record colour used for accents (progress, play ring); near-white when the record is black.
    var tintLight: Color {
        let c = UIColor(discColor)
        var h: CGFloat = 0, sat: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &sat, brightness: &b, alpha: &a)
        return sat < 0.1 ? Color(white: 0.92) : Color(hue: Double(h), saturation: Double(min(sat, 0.45)), brightness: 0.95)
    }

    var controlsRow: some View {
        HStack(spacing: 24) {
            btn(m.state.isPlaying ? "pause.fill" : "play.fill", m.state.isPlaying ? "Pause" : "Play") {
                if m.state.isPlaying { await m.provider?.pause() } else { await m.provider?.play() }
            }
            Spacer()
            btn("backward.fill", "Previous") { await m.provider?.previous() }
            btn("forward.fill", "Next") { await m.provider?.next() }
            if m.appleMusic != nil || CommandLine.arguments.contains("-ambrowser") {
                Button { showAM = true } label: {
                    Image(systemName: "square.stack").font(.system(size: 20)).foregroundStyle(.white.opacity(0.7)).frame(minWidth: 44, minHeight: 44)
                }.accessibilityLabel("Library")
            }
            if m.spotify != nil || (CommandLine.arguments.contains("-demo") && !CommandLine.arguments.contains("-ambrowser")) {
                Button { showQueue = true } label: {
                    Image(systemName: "list.bullet").font(.system(size: 20)).foregroundStyle(.white.opacity(0.7)).frame(minWidth: 44, minHeight: 44)
                }.accessibilityLabel("Queue")
                Button { showBrowser = true } label: {
                    Image(systemName: "square.stack").font(.system(size: 20)).foregroundStyle(.white.opacity(0.7)).frame(minWidth: 44, minHeight: 44)
                }.accessibilityLabel("Playlists")
            }
            Button { showSettings = true } label: {
                Image(systemName: "gearshape").font(.system(size: 20)).foregroundStyle(.white.opacity(0.7)).frame(minWidth: 44, minHeight: 44)
            }.accessibilityLabel("Settings")
        }
        .opacity(showControls ? 1 : 0)
        .allowsHitTesting(showControls)
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
                    HStack(spacing: 20) {
                        if m.appleMusic != nil || CommandLine.arguments.contains("-ambrowser") {
                            Button { showAM = true } label: {
                                Image(systemName: "square.stack").font(.system(size: 20)).foregroundStyle(.white.opacity(0.7)).frame(minWidth: 44, minHeight: 44)
                            }.accessibilityLabel("Library")
                        }
                        if m.spotify != nil || (CommandLine.arguments.contains("-demo") && !CommandLine.arguments.contains("-ambrowser")) {
                            Button { showQueue = true } label: {
                                Image(systemName: "list.bullet").font(.system(size: 20)).foregroundStyle(.white.opacity(0.7)).frame(minWidth: 44, minHeight: 44)
                            }.accessibilityLabel("Queue")
                            Button { showBrowser = true } label: {
                                Image(systemName: "square.stack").font(.system(size: 20)).foregroundStyle(.white.opacity(0.7)).frame(minWidth: 44, minHeight: 44)
                            }.accessibilityLabel("Playlists")
                        }
                        Button { showSettings = true } label: {
                            Image(systemName: "gearshape").font(.system(size: 20)).foregroundStyle(.white.opacity(0.7)).frame(minWidth: 44, minHeight: 44)
                        }.accessibilityLabel("Settings")
                    }
        }
        .opacity(showControls ? 1 : 0)
        .allowsHitTesting(showControls)
    }

    func fmt(_ t: TimeInterval) -> String { String(format: "%d:%02d", Int(t) / 60, Int(t) % 60) }

    func btn(_ icon: String, _ label: String, big: Bool = false, _ a: @escaping () async -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            reveal()
            Task { await a() }
        } label: {
            Image(systemName: icon).font(.system(size: big ? 52 : 26)).foregroundStyle(.white)
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel(label)
    }
}

/// Slim progress bar with a knob and a soft glow, like the Spotify-style reference.
struct GlowProgress: View {
    var value: Double
    var total: Double
    var tint: Color
    var body: some View {
        GeometryReader { g in
            let f = total > 0 ? CGFloat(min(max(value / total, 0), 1)) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.15)).frame(height: 4)
                Capsule().fill(tint).frame(width: g.size.width * f, height: 4).shadow(color: tint.opacity(0.7), radius: 5)
                Circle().fill(tint).frame(width: 14, height: 14).offset(x: max(0, g.size.width * f - 7))
            }.frame(maxHeight: .infinity)
        }.frame(height: 16)
    }
}

import SwiftUI
import Combine

@MainActor final class PlayerModel: ObservableObject {
    @Published var state = MusicState()
    @Published var art: UIImage?
    @Published var tint: Color = Color(white: 0.06)
    @Published var error: String?
    @Published var provider: MusicProvider?

    let artwork = ArtworkCenter()
    private var artBag: AnyCancellable?
    /// What the disc label shows: a chosen vinyl/custom artwork if any, otherwise the streaming cover.
    var discLabel: UIImage? { artwork.label ?? art }

    init() { artBag = artwork.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() } }

    private var artTask: Task<Void, Never>?
    private var busy = false   // a connect or restore is running

    private func apply(_ s: MusicState) {
        let changed = s.track?.id != state.track?.id
        let playChanged = s.isPlaying != state.isPlaying
        state = s
        if changed || playChanged { LiveActivityController.sync(s, tint: tint) }
        guard changed else { return }
        if let t = s.track, !CommandLine.arguments.contains("-demo") { artwork.albumChanged(artist: t.artist, album: t.album) }
        else if s.track == nil { artwork.albumChanged(artist: "", album: "") }
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
        // CI only: `-artquery "Artist|Album"` runs a real artwork lookup on the demo record.
        if let i = CommandLine.arguments.firstIndex(of: "-artquery"), i + 1 < CommandLine.arguments.count {
            let p = CommandLine.arguments[i + 1].split(separator: "|", maxSplits: 1).map(String.init)
            if p.count == 2 { artwork.albumChanged(artist: p[0], album: p[1]) }
        }
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
    @State private var showArtwork = CommandLine.arguments.contains("-artwork")
    @State private var showLyrics = CommandLine.arguments.contains("-lyrics")
    @State private var catalog: CatalogTarget? = {
        let a = CommandLine.arguments
        if a.contains("-artistpage") { return CatalogTarget(kind: .artist, artist: "Demo Artist") }
        if a.contains("-albumpage") { return CatalogTarget(kind: .album, artist: "Demo Artist", album: "Demo") }
        return nil
    }()
    @AppStorage(Pref.labelSize) private var labelSizePref = LabelSize.medium.rawValue
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
                // Landscape: the sleeve and the record as large as fits; a tap brings the controls back for a few seconds.
                composition(side)
                    .frame(width: g.size.width, height: g.size.height)
                    .contentShape(Rectangle())
                    .onTapGesture { if showControls && autoHide { hideTask?.cancel(); withAnimation(.easeIn(duration: 0.3)) { showControls = false } } else { reveal() } }
                    .overlay(alignment: .bottom) {
                        VStack(spacing: 12) { info(lm.showsProgress); controls }
                            .padding(.horizontal, 24).padding(.top, 40).padding(.bottom, 8)
                            .background(LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom))
                            .opacity(showControls ? 1 : 0).allowsHitTesting(showControls)
                    }
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
        .sheet(isPresented: $showLyrics) { LyricsView(m: m) }
        .sheet(item: $catalog) { CatalogView(m: m, target: $0) }
        .sheet(isPresented: $showArtwork) { ArtworkSelectorView(art: m.artwork, streamingCover: m.art) }
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
    var rim: AngularGradient {
        AngularGradient(stops: [
            .init(color: tintLight.opacity(0.12), location: 0.0), .init(color: tintLight.opacity(0.25), location: 0.2),
            .init(color: tintLight.opacity(0.7), location: 0.3), .init(color: tintLight, location: 0.4),
            .init(color: tintLight.opacity(0.9), location: 0.5), .init(color: tintLight.opacity(0.3), location: 0.58),
            .init(color: tintLight.opacity(0.7), location: 0.65), .init(color: tintLight, location: 0.72),
            .init(color: tintLight.opacity(0.35), location: 0.8), .init(color: tintLight.opacity(0.12), location: 0.92),
            .init(color: tintLight.opacity(0.12), location: 1.0)], center: .center)
    }

    func portrait(_ size: CGSize) -> some View {
        // Tall screens (iPad portrait) leave a big gap above the title: grow the record into it, but never into the ~330 pt controls block.
        let y0 = size.height * 0.06
        let d = max(120, min(size.width * 0.86, size.height * 0.56, size.height - y0 - 340))
        let x0 = (size.width - d) / 2 - size.width * 0.03
        let armLen = d * 0.535
        let aw = armLen * 0.16
        return ZStack(alignment: .topLeading) {
            Circle().fill(tintLight.opacity(0.22))   // soft purple haze behind the record
                .frame(width: d * 1.08, height: d * 1.08).blur(radius: 34)
                .offset(x: x0 - d * 0.04, y: y0 - d * 0.04)
            SpinningDisc(playing: m.state.isPlaying, color: discColor, label: m.discLabel, title: m.state.track?.title ?? "", labelScale: 0.46, inlineTitle: false)
                .frame(width: d, height: d)
                .contentShape(Circle()).discGestures(swipe: swipe, tap: discTapped)
                .offset(x: x0, y: y0)
            labelTarget(d).offset(x: x0 + d * (1 - labelFrac) / 2, y: y0 + d * (1 - labelFrac) / 2)
            Circle().strokeBorder(rim, lineWidth: 5)   // uneven glowing rim: bright arcs bottom-left and top-left
                .frame(width: d, height: d)
                .blur(radius: 1)
                .shadow(color: tintLight.opacity(0.9), radius: 12).shadow(color: tintLight.opacity(0.6), radius: 30)
                .allowsHitTesting(false)
                .offset(x: x0, y: y0)
            Tonearm(playing: m.state.isPlaying, length: armLen, playAngle: 12, glow: tintLight, onSet: setPlaying)
                .offset(x: x0 + d * 0.985 - aw * 1.1, y: y0 + d * 0.03 - aw * 1.1)
            VStack(alignment: .leading, spacing: 4) {
                Spacer()
                Button { openAlbum() } label: { Text(m.state.track?.title ?? "Nothing playing").font(.title2.bold()).lineLimit(2).multilineTextAlignment(.leading) }
                    .buttonStyle(.plain).foregroundStyle(.white).accessibilityHint("Opens the album")
                Button { openArtist() } label: { Text(m.state.track?.artist ?? "").font(.subheadline).foregroundStyle(tintLight).lineLimit(1) }
                    .buttonStyle(.plain).accessibilityHint("Opens the artist's discography")
                if let t = m.state.track, t.duration > 0 {
                    GlowProgress(value: min(m.state.progress, t.duration), total: t.duration, tint: tintLight, onSeek: seek).padding(.top, 6)
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

    var labelFrac: CGFloat { (LabelSize(rawValue: labelSizePref) ?? .medium).scaled(0.46) }

    /// Invisible target over the centre label: tap or swipe cycles the artwork, long-press opens the selector.
    /// Does not touch the spinning disc underneath, so rotation and playback are unaffected.
    func labelTarget(_ d: CGFloat) -> some View {
        Circle().fill(Color.white.opacity(0.001))
            .frame(width: d * labelFrac, height: d * labelFrac)
            .onTapGesture {
                if m.state.track == nil { discTapped() }
                else if m.artwork.variants.count > 1 { UISelectionFeedbackGenerator().selectionChanged(); m.artwork.cycle(1) }
                else { showArtwork = true }
            }
            .onLongPressGesture(minimumDuration: 0.45) { UIImpactFeedbackGenerator(style: .medium).impactOccurred(); showArtwork = true }
            .gesture(DragGesture(minimumDistance: 24).onEnded { g in
                guard abs(g.translation.width) > abs(g.translation.height), abs(g.translation.width) > 30 else { return }
                // Nothing to cycle: behave like the record, so previous/next track still works across the label.
                if m.artwork.variants.count <= 1 { swipe(g.translation.width); return }
                UISelectionFeedbackGenerator().selectionChanged(); m.artwork.cycle(g.translation.width < 0 ? 1 : -1)
            })
            .accessibilityLabel("Record label artwork").accessibilityHint("Double tap to change, long press for all editions")
    }

    /// Swipe on the record: left = previous track, right = next track (as the user asked).
    func swipe(_ dx: CGFloat) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred(); reveal()
        if CommandLine.arguments.contains("-demo") { return }
        Task { if dx < 0 { await m.provider?.previous() } else { await m.provider?.next() } }
    }
    /// Tap on the record while nothing is playing opens the music picker.
    func discTapped() {
        guard m.state.track == nil else { return }
        if m.appleMusic != nil { showAM = true }
        else if m.spotify != nil { showBrowser = true }
        else { showSettings = true }
    }

    func seek(_ t: Double) {
        reveal()
        if CommandLine.arguments.contains("-demo") { return }
        Task { await m.provider?.seek(to: t) }
    }

    /// Tonearm drag result: arm on the record plays, arm lifted pauses.
    func setPlaying(_ on: Bool) {
        if CommandLine.arguments.contains("-demo") { return }
        Task { if on { await m.provider?.play() } else { await m.provider?.pause() } }
    }

    func composition(_ side: CGFloat) -> some View {
        let discX = m.state.isPlaying ? side * 0.82 : side * 0.45
        let armLen = side * 0.72, aw = armLen * 0.16
        return ZStack(alignment: .topLeading) {
            Circle().fill(tintLight.opacity(0.22))   // soft haze behind the record
                .frame(width: side * 1.08, height: side * 1.08).blur(radius: 34)
                .offset(x: discX - side * 0.04, y: -side * 0.04)
            SpinningDisc(playing: m.state.isPlaying, color: discColor, label: m.discLabel, title: m.state.track?.title ?? "", labelScale: 0.46, inlineTitle: false)
                .frame(width: side, height: side)
                .contentShape(Circle()).discGestures(swipe: swipe, tap: discTapped)
                .offset(x: discX)
            labelTarget(side).offset(x: discX + side * (1 - labelFrac) / 2, y: side * (1 - labelFrac) / 2)
            Circle().strokeBorder(rim, lineWidth: 5)   // uneven glowing rim
                .frame(width: side, height: side).blur(radius: 1)
                .shadow(color: tintLight.opacity(0.9), radius: 12).shadow(color: tintLight.opacity(0.6), radius: 30)
                .allowsHitTesting(false)
                .offset(x: discX)
            Group {
                if let a = m.art { Image(uiImage: a).resizable().scaledToFill() } else { Color(white: 0.15) }
            }
            .frame(width: side, height: side).clipped()
            .shadow(color: .black.opacity(0.7), radius: 24, y: 14)
            Tonearm(playing: m.state.isPlaying, length: armLen, playAngle: 12, glow: tintLight, onSet: setPlaying)
                .offset(x: side * 1.82 - aw * 1.1, y: side * 0.03 - aw * 1.1)
        }
        .animation(.spring(response: 0.9, dampingFraction: 0.85), value: m.state.isPlaying)
        .frame(width: side * 1.95, height: side, alignment: .topLeading)
        .accessibilityHidden(true)
    }
    func info(_ progress: Bool) -> some View {
        VStack(spacing: 14) {
        VStack(spacing: 4) {
                        Button { openAlbum() } label: { Text(m.state.track?.title ?? "Nothing playing").font(.title3.bold()) }
                            .buttonStyle(.plain).accessibilityHint("Opens the album")
                        Button { openArtist() } label: { Text(m.state.track?.artist ?? "").font(.subheadline).foregroundStyle(.white.opacity(0.65)) }
                            .buttonStyle(.plain).accessibilityHint("Opens the artist's discography")
                    }
                    .foregroundStyle(.white)

                    if progress, let t = m.state.track, t.duration > 0 {
                        GlowProgress(value: min(m.state.progress, t.duration), total: t.duration, tint: .white, onSeek: seek)
                            .padding(.horizontal, 40)
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

    func openArtist() {
        guard let t = m.state.track, !t.artist.isEmpty else { return }
        reveal()
        catalog = CatalogTarget(kind: .artist, artist: t.artist, artistID: t.artistID)
    }
    func openAlbum() {
        guard let t = m.state.track, !t.album.isEmpty else { return }
        reveal()
        catalog = CatalogTarget(kind: .album, artist: t.artist, album: t.album, artistID: t.artistID, albumID: t.albumID)
    }

    /// Library / queue / playlists / settings icons.
    var utilityRow: some View {
        HStack(spacing: 28) {
            Spacer()
            if m.appleMusic != nil || CommandLine.arguments.contains("-ambrowser") {
                Button { showAM = true } label: { utilIcon("square.stack") }.accessibilityLabel("Library")
            }
            if m.spotify != nil || (CommandLine.arguments.contains("-demo") && !CommandLine.arguments.contains("-ambrowser")) {
                Button { showBrowser = true } label: { utilIcon("square.stack") }.accessibilityLabel("Playlists")
            }
            Button { showSettings = true } label: { utilIcon("gearshape") }.accessibilityLabel("Settings")
            Button { showQueue = true } label: { utilIcon("list.bullet") }.accessibilityLabel("Queue")
            Button { showLyrics = true } label: { utilIcon("quote.bubble") }.accessibilityLabel("Lyrics")
            Button { showArtwork = true } label: { utilIcon("opticaldisc") }.accessibilityLabel("Vinyl artwork")
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
                Button { showBrowser = true } label: {
                    Image(systemName: "square.stack").font(.system(size: 20)).foregroundStyle(.white.opacity(0.7)).frame(minWidth: 44, minHeight: 44)
                }.accessibilityLabel("Playlists")
            }
            Button { showSettings = true } label: {
                Image(systemName: "gearshape").font(.system(size: 20)).foregroundStyle(.white.opacity(0.7)).frame(minWidth: 44, minHeight: 44)
            }.accessibilityLabel("Settings")
            Button { showQueue = true } label: {
                Image(systemName: "list.bullet").font(.system(size: 20)).foregroundStyle(.white.opacity(0.7)).frame(minWidth: 44, minHeight: 44)
            }.accessibilityLabel("Queue")
            Button { showLyrics = true } label: {
                Image(systemName: "quote.bubble").font(.system(size: 20)).foregroundStyle(.white.opacity(0.7)).frame(minWidth: 44, minHeight: 44)
            }.accessibilityLabel("Lyrics")
        }
        .opacity(showControls ? 1 : 0)
        .allowsHitTesting(showControls)
    }

    var controls: some View {
        VStack(spacing: 18) {
                    HStack(spacing: 30) {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred(); reveal()
                            Task { await m.provider?.setShuffle(!m.state.shuffle) }
                        } label: { modeIcon("shuffle", on: m.state.shuffle) }.accessibilityLabel("Shuffle")
                        btn("backward.fill", "Previous") { await m.provider?.previous() }
                        btn(m.state.isPlaying ? "pause.circle.fill" : "play.circle.fill",
                            m.state.isPlaying ? "Pause" : "Play", big: true) {
                            if m.state.isPlaying { await m.provider?.pause() } else { await m.provider?.play() }
                        }
                        btn("forward.fill", "Next") { await m.provider?.next() }
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred(); reveal()
                            Task { await m.provider?.setRepeat(m.state.repeatMode.next) }
                        } label: { modeIcon(m.state.repeatMode == .one ? "repeat.1" : "repeat", on: m.state.repeatMode != .off) }
                            .accessibilityLabel("Repeat")
                    }
                    HStack(spacing: 20) {
                        if m.appleMusic != nil || CommandLine.arguments.contains("-ambrowser") {
                            Button { showAM = true } label: {
                                Image(systemName: "square.stack").font(.system(size: 20)).foregroundStyle(.white.opacity(0.7)).frame(minWidth: 44, minHeight: 44)
                            }.accessibilityLabel("Library")
                        }
                        if m.spotify != nil || (CommandLine.arguments.contains("-demo") && !CommandLine.arguments.contains("-ambrowser")) {
                            Button { showBrowser = true } label: {
                                Image(systemName: "square.stack").font(.system(size: 20)).foregroundStyle(.white.opacity(0.7)).frame(minWidth: 44, minHeight: 44)
                            }.accessibilityLabel("Playlists")
                        }
                        Button { showSettings = true } label: {
                            Image(systemName: "gearshape").font(.system(size: 20)).foregroundStyle(.white.opacity(0.7)).frame(minWidth: 44, minHeight: 44)
                        }.accessibilityLabel("Settings")
                        Button { showQueue = true } label: {
                            Image(systemName: "list.bullet").font(.system(size: 20)).foregroundStyle(.white.opacity(0.7)).frame(minWidth: 44, minHeight: 44)
                        }.accessibilityLabel("Queue")
                        Button { showLyrics = true } label: {
                            Image(systemName: "quote.bubble").font(.system(size: 20)).foregroundStyle(.white.opacity(0.7)).frame(minWidth: 44, minHeight: 44)
                        }.accessibilityLabel("Lyrics")
                        Button { showArtwork = true } label: {
                            Image(systemName: "opticaldisc").font(.system(size: 20)).foregroundStyle(.white.opacity(0.7)).frame(minWidth: 44, minHeight: 44)
                        }.accessibilityLabel("Vinyl artwork")
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

/// Slim progress bar with a knob and a soft glow. Tap or drag to seek; the seek is sent when the finger lifts.
struct GlowProgress: View {
    var value: Double
    var total: Double
    var tint: Color
    var onSeek: ((Double) -> Void)? = nil
    @State private var dragFrac: Double?
    var body: some View {
        GeometryReader { g in
            let live = total > 0 ? min(max(value / total, 0), 1) : 0
            let f = CGFloat(dragFrac ?? live)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.15)).frame(height: 4)
                Capsule().fill(tint).frame(width: g.size.width * f, height: 4).shadow(color: tint.opacity(0.7), radius: 5)
                Circle().fill(tint).frame(width: dragFrac == nil ? 14 : 20, height: dragFrac == nil ? 14 : 20)
                    .offset(x: max(0, g.size.width * f - (dragFrac == nil ? 7 : 10)))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in dragFrac = Double(min(max(v.location.x / max(g.size.width, 1), 0), 1)) }
                .onEnded { v in
                    let fr = Double(min(max(v.location.x / max(g.size.width, 1), 0), 1))
                    dragFrac = nil
                    onSeek?(fr * total)
                })
        }.frame(height: 32)
    }
}


extension View {
    /// Horizontal swipe (>40 pt) and plain tap on the record.
    func discGestures(swipe: @escaping (CGFloat) -> Void, tap: @escaping () -> Void) -> some View {
        self.onTapGesture(perform: tap)
            .gesture(DragGesture(minimumDistance: 30).onEnded { g in
                if abs(g.translation.width) > 40, abs(g.translation.width) > abs(g.translation.height) { swipe(g.translation.width) }
            })
    }
}

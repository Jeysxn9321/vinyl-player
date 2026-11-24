import SwiftUI

@main struct VinylApp: App {
    @StateObject private var model = PlayerModel()
    /// `-frame 740x540` renders the player at a fixed size (layout QA for foldable-sized canvases).
    static var demoSize: CGSize? {
        guard let i = CommandLine.arguments.firstIndex(of: "-frame"), i + 1 < CommandLine.arguments.count else { return nil }
        let p = CommandLine.arguments[i + 1].split(separator: "x").compactMap { Double($0) }
        return p.count == 2 ? CGSize(width: p[0], height: p[1]) : nil
    }
    var body: some Scene {
        WindowGroup {
            if CommandLine.arguments.contains("-card") {
                // CI screenshot of the Live Activity lock-screen card (simctl cannot lock the screen).
                ZStack {
                    LinearGradient(colors: [.indigo, .black], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                    NowPlayingCard(s: .init(title: "Family Matters", artist: "Demo Artist", isPlaying: true,
                                            start: Date().addingTimeInterval(-83), end: Date().addingTimeInterval(157),
                                            progress: 0.35, tintR: 0.9, tintG: 0.55, tintB: 0.25))
                        .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 24)).padding()
                }
            } else if CommandLine.arguments.contains("-demo") {
                PlayerView(m: model).frame(width: Self.demoSize?.width, height: Self.demoSize?.height).onAppear {
                    model.loadDemo()
                    if CommandLine.arguments.contains("-pill") { model.state = MusicState(provider: .spotify) }
                    if CommandLine.arguments.contains("-landscape"),
                       let sc = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                        sc.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight))
                    }
                }
            } else if model.provider == nil { Onboarding(model: model).task { await model.restore() } } else { PlayerView(m: model) }
        }
    }
}

struct Onboarding: View {
    @ObservedObject var model: PlayerModel
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 20) {
                Text("Lunara").font(.system(size: 44, weight: .thin)).foregroundStyle(.white)
                Text("Choose where your music lives.").foregroundStyle(.secondary)
                Button("Apple Music") { Task { await model.connect(AppleMusicProvider()) } }
                    .buttonStyle(.borderedProminent)
                Button("Spotify") { Task { await model.connect(SpotifyProvider()) } }
                    .buttonStyle(.bordered)
                if let e = model.error {
                    Text(e).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center).padding()
                }
            }
        }
    }
}

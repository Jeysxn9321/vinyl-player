import SwiftUI

@main struct VinylApp: App {
    @StateObject private var model = PlayerModel()
    var body: some Scene {
        WindowGroup {
            if model.provider == nil { Onboarding(model: model) } else { PlayerView(m: model) }
        }
    }
}

struct Onboarding: View {
    @ObservedObject var model: PlayerModel
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 20) {
                Text("Vinyl").font(.system(size: 44, weight: .thin)).foregroundStyle(.white)
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

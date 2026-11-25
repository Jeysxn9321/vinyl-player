import SwiftUI
import AVKit

/// Long-press menu on a song row: "Play next" (Apple Music only, Spotify has no such call) and "Add to queue".
struct QueueActions: ViewModifier {
    let m: PlayerModel
    let song: SongItem
    @State private var note: String?

    func body(content: Content) -> some View {
        content
            .contextMenu {
                if !isSpotify {
                    Button { run(next: true) } label: { Label("Play next", systemImage: "text.insert") }
                }
                Button { run(next: false) } label: { Label("Add to queue", systemImage: "text.append") }
            }
            .overlay(alignment: .trailing) {
                if let note {
                    Text(note).font(.caption.weight(.medium)).foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule()).transition(.opacity)
                }
            }
    }

    private var isSpotify: Bool { song.id.hasPrefix("spotify:") }

    private func run(next: Bool) {
        Task {
            let err: String?
            if isSpotify { err = await m.spotify?.enqueue(uri: song.id) ?? "Spotify isn't connected." }
            else { err = await m.appleMusic?.enqueue(song, next: next) ?? "Apple Music isn't connected." }
            withAnimation { note = err ?? (next ? "Playing next" : "Added to queue") }
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            withAnimation { note = nil }
        }
    }
}

extension View {
    func queueActions(_ m: PlayerModel, _ song: SongItem) -> some View { modifier(QueueActions(m: m, song: song)) }
}

/// System AirPlay picker. It routes this device's audio, so it only means something for Apple Music;
/// Spotify plays on its own Connect device.
struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.tintColor = UIColor.white.withAlphaComponent(0.7)
        v.activeTintColor = .white
        v.prioritizesVideoDevices = false
        return v
    }
    func updateUIView(_ v: AVRoutePickerView, context: Context) {}
}

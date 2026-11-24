import SwiftUI

/// Read-only "Up next" list from Spotify's queue. Spotify has no call to jump to a queue item without
/// dropping the playlist context, so rows are not tappable.
struct QueueView: View {
    @ObservedObject var m: PlayerModel
    @Environment(\.dismiss) private var dismiss
    @State private var queue: SpotifyProvider.Queue?
    @State private var message: String?
    private var demo: Bool { CommandLine.arguments.contains("-demo") }

    var body: some View {
        NavigationStack {
            List {
                if let message { Text(message).foregroundStyle(.orange) }
                if let now = queue?.now {
                    Section("Now playing") { row(now) }
                }
                if let up = queue?.upNext, !up.isEmpty {
                    Section("Up next") { ForEach(up) { row($0) } }
                } else if queue != nil {
                    Text("The queue is empty.").foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Queue")
            .toolbar { Button("Done") { dismiss() } }
            .task(id: m.state.track?.id) { await load() }
        }
        .preferredColorScheme(.dark)
    }

    func row(_ i: SpotifyProvider.QueueItem) -> some View {
        HStack(spacing: 12) {
            AsyncImage(url: i.imageURL) { $0.resizable().scaledToFill() } placeholder: { Color(white: 0.25) }
                .frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(i.title).lineLimit(1)
                if !i.subtitle.isEmpty { Text(i.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
        }
    }

    func load() async {
        if demo {
            let names = ["Late Night Drive", "Chill Sunday", "Neon Coast", "Paper Planes", "Slow Burn"]
            queue = .init(now: .init(id: 0, title: "Family Matters", subtitle: "Demo Artist", imageURL: nil),
                          upNext: names.enumerated().map { .init(id: $0.offset + 1, title: $0.element, subtitle: "Demo Artist", imageURL: nil) })
            return
        }
        do { queue = try await m.spotify?.queue(); message = nil }
        catch SpotifyProvider.BrowseError.needsReconnect { message = "Spotify refused the queue request. Try Reconnect from Playlists." }
        catch { message = "Couldn't load the queue." }
    }
}

import SwiftUI

/// "Up next" list. Tapping a row jumps there: Spotify by skipping forward that many tracks (keeps the context),
/// Apple Music by selecting the queue entry.
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
                    Section("Up next") { ForEach(up) { i in Button { Task { await jump(i) } } label: { row(i) }.buttonStyle(.plain) } }
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
            ArtThumb(url: i.imageURL, artwork: i.artwork, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(i.title).lineLimit(1)
                if !i.subtitle.isEmpty { Text(i.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
        }
    }

    func jump(_ i: SpotifyProvider.QueueItem) async {
        if demo { dismiss(); return }
        if let am = m.appleMusic { await am.jump(toRow: i.id, from: queue?.now?.id ?? 0) }
        else { await m.spotify?.skip(forward: i.id) }
        dismiss()
    }

    func load() async {
        if demo {
            let names = ["Late Night Drive", "Chill Sunday", "Neon Coast", "Paper Planes", "Slow Burn"]
            queue = .init(now: .init(id: 0, title: "Family Matters", subtitle: "Demo Artist", imageURL: nil),
                          upNext: names.enumerated().map { .init(id: $0.offset + 1, title: $0.element, subtitle: "Demo Artist", imageURL: nil) })
            return
        }
        if let am = m.appleMusic { queue = am.queue(); message = nil; return }
        do { queue = try await m.spotify?.queue(); message = nil }
        catch SpotifyProvider.BrowseError.needsReconnect { message = "Spotify refused the queue request. Try Reconnect from Playlists." }
        catch { message = "Couldn't load the queue." }
    }
}

import SwiftUI

/// Apple Music library browser: playlists and albums, tap to start playback in Lunara's own player.
/// `-demo` shows stub rows and never touches MusicKit (it does not work in the simulator).
struct AppleMusicLibraryView: View {
    @ObservedObject var m: PlayerModel
    @Environment(\.dismiss) private var dismiss
    @State private var items: [AMItem] = []
    @State private var query = ""
    @State private var loading = true
    @State private var message: String?
    private var demo: Bool { CommandLine.arguments.contains("-demo") }

    private var shown: [AMItem] { query.isEmpty ? items : items.filter { $0.name.localizedCaseInsensitiveContains(query) } }

    var body: some View {
        NavigationStack {
            List {
                if let message { Text(message).foregroundStyle(.orange) }
                if loading { ProgressView() }
                else if shown.isEmpty { Text(items.isEmpty ? "Your Apple Music library is empty, or access failed." : "No match.").foregroundStyle(.secondary) }
                ForEach(shown) { item in
                    Button { Task { await play(item) } } label: {
                        HStack(spacing: 12) {
                            AsyncImage(url: item.imageURL) { $0.resizable().scaledToFill() } placeholder: {
                                Color(white: 0.2)
                            }
                            .frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 6))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name).lineLimit(1)
                                Text(item.isAlbum ? "Album, \(item.subtitle)" : item.subtitle)
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Search your library")
            .navigationTitle("Library")
            .toolbar { Button("Done") { dismiss() } }
            .task { await load() }
        }
        .preferredColorScheme(.dark)
    }

    func load() async {
        defer { loading = false }
        if demo {
            items = [AMItem(id: "1", name: "Favourites Mix", subtitle: "Playlist", imageURL: nil, isAlbum: false),
                     AMItem(id: "2", name: "Late Night Drive", subtitle: "Playlist", imageURL: nil, isAlbum: false),
                     AMItem(id: "3", name: "Debí Tirar Más Fotos", subtitle: "Bad Bunny", imageURL: nil, isAlbum: true),
                     AMItem(id: "4", name: "Random Access Memories", subtitle: "Daft Punk", imageURL: nil, isAlbum: true)]
            return
        }
        do { items = try await m.appleMusic?.library() ?? [] }
        catch { message = "Couldn't load your library: \(error.localizedDescription)" }
    }

    func play(_ item: AMItem) async {
        if demo { dismiss(); return }
        if let e = await m.appleMusic?.play(item) { message = e } else { dismiss() }
    }
}

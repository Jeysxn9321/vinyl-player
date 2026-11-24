import SwiftUI

/// Apple Music library browser: tap a playlist/album to see its songs, search the catalog, play inside Lunara's own player.
/// `-demo` shows stub rows and never touches MusicKit (it does not work in the simulator).
struct AppleMusicLibraryView: View {
    @ObservedObject var m: PlayerModel
    @Environment(\.dismiss) private var dismiss
    @State private var items: [AMItem] = []
    @State private var query = UserDefaults.standard.string(forKey: "amquery") ?? ""   // `-amquery x` for CI shots
    @State private var selected: AMItem?
    @State private var songs: [SongItem] = []
    @State private var searching = false
    @State private var loading = true
    @State private var message: String?
    @State private var searchError: String?
    private var demo: Bool { CommandLine.arguments.contains("-demo") }

    private var shown: [AMItem] { query.isEmpty ? items : items.filter { $0.name.localizedCaseInsensitiveContains(query) } }

    var body: some View {
        NavigationStack {
            List {
                if let message { Text(message).foregroundStyle(.orange) }
                if loading { ProgressView() }
                else if shown.isEmpty { Text(items.isEmpty ? "Your Apple Music library is empty, or access failed." : "No match.").foregroundStyle(.secondary) }
                if !query.isEmpty {
                    Section("Songs") {
                        if searching { ProgressView() }
                        else if let searchError { Text(searchError).font(.footnote).foregroundStyle(.orange) }
                        else if songs.isEmpty { Text(query.count < 2 ? "Keep typing to search Apple Music." : "No songs found.").foregroundStyle(.secondary) }
                        ForEach(songs) { s in
                            Button { Task { await playSong(s) } } label: { SongRow(s: s) }.buttonStyle(.plain)
                        }
                    }
                }
                ForEach(shown) { item in
                    Button { selected = item } label: {
                        HStack(spacing: 12) {
                            ArtThumb(url: item.imageURL, artwork: item.artwork, size: 48)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name).lineLimit(1)
                                Text(item.isAlbum ? "Album, \(item.subtitle)" : item.subtitle)
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Search library and Apple Music")
            .task(id: query) { await search() }
            .navigationDestination(item: $selected) { item in
                AMTracksView(m: m, item: item, onPlayed: { dismiss() })
            }
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
            if CommandLine.arguments.contains("-amtracks") { selected = items.first }
            return
        }
        do { items = try await m.appleMusic?.library() ?? [] }
        catch { message = "Couldn't load your library: \(error.localizedDescription)" }
    }

    func playSong(_ s: SongItem) async {
        if demo { dismiss(); return }
        if let e = await m.appleMusic?.play(songID: s.id, fromList: false) { message = e } else { dismiss() }
    }

    func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { songs = []; return }
        try? await Task.sleep(nanoseconds: 350_000_000)
        guard !Task.isCancelled else { return }
        searching = true; defer { searching = false }
        if demo { songs = DemoSongs.all; return }
        do { songs = try await m.appleMusic?.search(q) ?? []; searchError = nil }
        catch { songs = []; searchError = "Apple Music search failed: \(error.localizedDescription)" }
    }
}

import SwiftUI

/// Apple Music library browser: tap a playlist/album to see its songs, search the catalog, play inside Lunara's own player.
/// `-demo` shows stub rows and never touches MusicKit (it does not work in the simulator).
struct AppleMusicLibraryView: View {
    @ObservedObject var m: PlayerModel
    @Environment(\.dismiss) private var dismiss
    @State private var items: [AMItem] = []
    @State private var query = UserDefaults.standard.string(forKey: "amquery") ?? ""   // `-amquery x` for CI shots
    @State private var selected: AMItem?
    @State private var results = AMSearch()
    @State private var chart: [CatalogAlbum] = []
    @State private var album: CatalogAlbum?
    @State private var artist: AMArtist?
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
                if query.isEmpty {
                    if !chart.isEmpty {
                        Section("Top albums") {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 14) { ForEach(chart) { a in
                                    Button { album = a } label: {
                                        VStack(alignment: .leading, spacing: 4) {
                                            ArtThumb(url: a.imageURL, artwork: nil, size: 110)
                                            Text(a.title).font(.caption.bold()).lineLimit(1)
                                            Text(a.artist).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                        }.frame(width: 110, alignment: .leading)
                                    }.buttonStyle(.plain)
                                } }
                            }.listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        }
                    }
                } else {
                    if searching { ProgressView() }
                    else if let searchError { Text(searchError).font(.footnote).foregroundStyle(.orange) }
                    else if results.isEmpty { Text(query.count < 2 ? "Keep typing to search Apple Music." : "Nothing found.").foregroundStyle(.secondary) }
                    if !results.songs.isEmpty {
                        Section("Songs") {
                            ForEach(results.songs) { s in
                                Button { Task { await playSong(s) } } label: { SongRow(s: s) }.buttonStyle(.plain).queueActions(m, s)
                            }
                        }
                    }
                    if !results.albums.isEmpty {
                        Section("Albums") {
                            ForEach(results.albums) { a in
                                Button { album = a } label: {
                                    HStack(spacing: 12) {
                                        ArtThumb(url: a.imageURL, artwork: nil, size: 48)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(a.title).lineLimit(1)
                                            Text([a.artist, a.year].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    if !results.playlists.isEmpty {
                        Section("Playlists") {
                            ForEach(results.playlists) { p in
                                Button { selected = p } label: {
                                    HStack(spacing: 12) {
                                        ArtThumb(url: p.imageURL, artwork: p.artwork, size: 48)
                                        Text(p.name).lineLimit(1)
                                    }
                                }
                            }
                        }
                    }
                    if !results.artists.isEmpty {
                        Section("Artists") {
                            ForEach(results.artists) { a in
                                Button { artist = a } label: { Label(a.name, systemImage: "music.mic").foregroundStyle(.primary) }
                            }
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
            .navigationDestination(item: $album) { a in AlbumTracksView(m: m, album: a, onPlayed: { dismiss() }) }
            .navigationDestination(item: $artist) { a in AMArtistView(m: m, artist: a, onPlayed: { dismiss() }) }
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
            chart = CatalogService.demoAlbums
            if CommandLine.arguments.contains("-amtracks") { selected = items.first }
            return
        }
        Task { chart = (try? await m.appleMusic?.topAlbums()) ?? [] }
        do { items = try await m.appleMusic?.library() ?? [] }
        catch { message = "Couldn't load your library: \(error.localizedDescription)" }
    }

    func playSong(_ s: SongItem) async {
        if demo { dismiss(); return }
        if let e = await m.appleMusic?.play(songID: s.id, fromList: false) { message = e } else { dismiss() }
    }

    func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { results = AMSearch(); return }
        try? await Task.sleep(nanoseconds: 350_000_000)
        guard !Task.isCancelled else { return }
        searching = true; defer { searching = false }
        if demo { results = AMSearch(songs: DemoSongs.all, albums: CatalogService.demoAlbums, artists: [AMArtist(id: "1", name: "Demo Artist")]); return }
        do { results = try await m.appleMusic?.searchAll(q) ?? AMSearch(); searchError = nil }
        catch { results = AMSearch(); searchError = "Apple Music search failed: \(error.localizedDescription)" }
    }
}

/// One artist's albums, opened from search results.
struct AMArtistView: View {
    @ObservedObject var m: PlayerModel
    let artist: AMArtist
    var onPlayed: () -> Void
    @State private var albums: [CatalogAlbum] = []
    @State private var loading = true
    @State private var message: String?
    @State private var selected: CatalogAlbum?

    var body: some View {
        List {
            if let message { Text(message).foregroundStyle(.orange) }
            if loading { ProgressView() }
            else if albums.isEmpty, message == nil { Text("No albums found.").foregroundStyle(.secondary) }
            ForEach(albums) { a in
                Button { selected = a } label: {
                    HStack(spacing: 12) {
                        ArtThumb(url: a.imageURL, artwork: nil, size: 56)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(a.title).lineLimit(2)
                            if !a.year.isEmpty { Text(a.year).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }.buttonStyle(.plain)
            }
        }
        .navigationTitle(artist.name).navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selected) { a in AlbumTracksView(m: m, album: a, onPlayed: onPlayed) }
        .task {
            defer { loading = false }
            if CommandLine.arguments.contains("-demo") { albums = CatalogService.demoAlbums; return }
            do { albums = try await m.appleMusic?.artistAlbums(name: artist.name, id: artist.id) ?? [] }
            catch { message = "Couldn't load this artist. Check your connection." }
        }
    }
}

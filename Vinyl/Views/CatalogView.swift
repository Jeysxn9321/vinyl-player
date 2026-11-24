import SwiftUI

/// One album in an artist's discography.
struct CatalogAlbum: Identifiable, Hashable {
    var id: String
    var title: String
    var artist: String
    var year: String
    var imageURL: URL?
}

/// What the player asked to open: an artist's discography or the album of the playing song.
struct CatalogTarget: Identifiable {
    enum Kind { case artist, album }
    var kind: Kind
    var artist: String
    var album: String = ""
    var artistID: String? = nil
    var albumID: String? = nil
    var id: String { "\(kind)|\(artist)|\(album)" }
}

/// Routes catalog lookups to whichever service is connected. `-demo` uses stub data and never touches the network.
@MainActor struct CatalogService {
    let m: PlayerModel
    var demo: Bool { CommandLine.arguments.contains("-demo") }
    private var spotify: SpotifyProvider? { m.provider?.kind == .appleMusic ? nil : m.spotify }
    private var apple: AppleMusicProvider? { m.provider?.kind == .spotify ? nil : m.appleMusic }

    static let demoAlbums = [
        CatalogAlbum(id: "a1", title: "Demo Album", artist: "Demo Artist", year: "2024", imageURL: nil),
        CatalogAlbum(id: "a2", title: "Late Night EP", artist: "Demo Artist", year: "2022", imageURL: nil),
        CatalogAlbum(id: "a3", title: "First Press", artist: "Demo Artist", year: "2019", imageURL: nil),
    ]

    func albums(artist: String, id: String?) async throws -> [CatalogAlbum] {
        if demo { return Self.demoAlbums }
        if let s = spotify { return try await s.artistAlbums(name: artist, id: id) }
        if let a = apple { return try await a.artistAlbums(name: artist, id: id) }
        return []
    }
    func resolve(album: String, artist: String, id: String?) async throws -> CatalogAlbum? {
        if demo { return Self.demoAlbums[0] }
        if let s = spotify { return try await s.findAlbum(title: album, artist: artist, id: id) }
        if let a = apple { return try await a.findAlbum(title: album, artist: artist, id: id) }
        return nil
    }
    func tracks(_ album: CatalogAlbum) async throws -> [SongItem] {
        if demo { return DemoSongs.all }
        if let s = spotify { return try await s.albumTracks(album) }
        if let a = apple { return try await a.albumTracks(album) }
        return []
    }
    /// Returns an error message, or nil on success.
    func play(_ album: CatalogAlbum, songs: [SongItem], start: SongItem?) async -> String? {
        if demo { return nil }
        if let s = spotify { return await s.play(album: album, start: start) }
        if let a = apple { return await a.play(album: songs, start: start) }
        return "Connect Spotify or Apple Music first."
    }
}

/// Sheet opened by tapping the artist (discography) or the song title (its album) on the player.
struct CatalogView: View {
    @ObservedObject var m: PlayerModel
    let target: CatalogTarget
    @Environment(\.dismiss) private var dismiss
    @State private var albums: [CatalogAlbum] = []
    @State private var single: CatalogAlbum?
    @State private var loading = true
    @State private var message: String?
    @State private var selected: CatalogAlbum?

    var body: some View {
        NavigationStack {
            Group {
                if target.kind == .album {
                    if let single { AlbumTracksView(m: m, album: single, onPlayed: { dismiss() }) }
                    else { status }
                } else {
                    List {
                        if let message { Text(message).foregroundStyle(.orange) }
                        if loading { ProgressView() }
                        else if albums.isEmpty, message == nil { Text("No albums found.").foregroundStyle(.secondary) }
                        ForEach(albums) { a in
                            Button { selected = a } label: {
                                HStack(spacing: 12) {
                                    ArtThumb(url: a.imageURL, artwork: nil, size: 56)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(a.title).lineLimit(2).foregroundStyle(.primary)
                                        if !a.year.isEmpty { Text(a.year).font(.caption).foregroundStyle(.secondary) }
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                                }.contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                    .navigationDestination(item: $selected) { a in AlbumTracksView(m: m, album: a, onPlayed: { dismiss() }) }
                }
            }
            .navigationTitle(target.kind == .artist ? target.artist : target.album).navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
            .task { await load() }
        }
        .preferredColorScheme(.dark)
    }

    private var status: some View {
        VStack(spacing: 12) {
            if loading { ProgressView() }
            Text(message ?? (loading ? "" : "Couldn't find this album.")).foregroundStyle(.secondary).multilineTextAlignment(.center).padding()
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func load() async {
        defer { loading = false }
        let svc = CatalogService(m: m)
        do {
            if target.kind == .artist { albums = try await svc.albums(artist: target.artist, id: target.artistID) }
            else { single = try await svc.resolve(album: target.album, artist: target.artist, id: target.albumID) }
        } catch SpotifyProvider.BrowseError.needsReconnect {
            message = "Spotify needs a fresh sign-in. Use Reconnect in Settings."
        } catch SpotifyProvider.BrowseError.forbidden {
            message = "Spotify refused this request for your account."
        } catch { message = "Couldn't load this. Check your connection." }
    }
}

/// Songs of one album; tap a song to play the album from there.
struct AlbumTracksView: View {
    @ObservedObject var m: PlayerModel
    let album: CatalogAlbum
    var onPlayed: () -> Void
    @State private var songs: [SongItem] = []
    @State private var loading = true
    @State private var message: String?

    var body: some View {
        List {
            HStack(spacing: 14) {
                ArtThumb(url: album.imageURL, artwork: nil, size: 84)
                VStack(alignment: .leading, spacing: 3) {
                    Text(album.title).font(.headline).lineLimit(2)
                    Text([album.artist, album.year].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                }
            }
            Button { Task { await play(nil) } } label: { Label("Play album", systemImage: "play.circle.fill") }
            if let message { Text(message).foregroundStyle(.orange) }
            if loading { ProgressView() }
            else if songs.isEmpty, message == nil { Text("No songs found.").foregroundStyle(.secondary) }
            ForEach(songs) { s in
                Button { Task { await play(s) } } label: { SongRow(s: s) }.buttonStyle(.plain)
            }
        }
        .navigationTitle(album.title).navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    func load() async {
        defer { loading = false }
        do { songs = try await CatalogService(m: m).tracks(album) }
        catch { message = "Couldn't load the songs. Check your connection." }
    }
    func play(_ s: SongItem?) async {
        if let e = await CatalogService(m: m).play(album, songs: songs, start: s) { message = e } else { onPlayed() }
    }
}

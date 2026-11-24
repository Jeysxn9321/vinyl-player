import SwiftUI

/// One playable song row, shared by the Spotify and Apple Music browsers. `id` is the service's own ID (Spotify: URI).
struct SongItem: Identifiable, Hashable {
    var id: String
    var title: String
    var artist: String
    var imageURL: URL?
}

struct SongRow: View {
    var s: SongItem
    var showsPlay = true
    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: s.imageURL) { $0.resizable().scaledToFill() } placeholder: { Color(white: 0.22) }
                .frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(s.title).lineLimit(1).foregroundStyle(.primary)
                if !s.artist.isEmpty { Text(s.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 0)
            if showsPlay { Image(systemName: "play.fill").font(.caption).foregroundStyle(.secondary) }
        }
        .contentShape(Rectangle())
    }
}

/// Stub rows for `-demo` (CI screenshots); the demo path never calls Spotify or MusicKit.
enum DemoSongs {
    static let all: [SongItem] = [
        .init(id: "d1", title: "Family Matters", artist: "Demo Artist", imageURL: nil),
        .init(id: "d2", title: "Late Night Drive", artist: "Demo Artist", imageURL: nil),
        .init(id: "d3", title: "Neon Coast", artist: "Another Band", imageURL: nil),
        .init(id: "d4", title: "Paper Planes", artist: "Another Band", imageURL: nil),
        .init(id: "d5", title: "Slow Burn", artist: "Demo Artist", imageURL: nil),
    ]
}

/// Tracks of one Spotify playlist; tap a song to play it inside its playlist.
struct SpotifyTracksView: View {
    @ObservedObject var m: PlayerModel
    let playlist: SpotifyProvider.Playlist
    var onPlayed: () -> Void
    @State private var songs: [SongItem] = []
    @State private var loading = true
    @State private var message: String?
    @State private var note: String?
    private var demo: Bool { CommandLine.arguments.contains("-demo") }

    var body: some View {
        List {
            Button { Task { await playAll() } } label: { Label("Play playlist", systemImage: "play.circle.fill") }
            if let message { Text(message).foregroundStyle(.orange) }
            if let note { Text(note).font(.footnote).foregroundStyle(.secondary) }
            if loading { ProgressView() }
            ForEach(songs) { s in
                Button { Task { await play(s) } } label: { SongRow(s: s) }.buttonStyle(.plain)
            }
        }
        .navigationTitle(playlist.name).navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    func load() async {
        defer { loading = false }
        if demo { songs = DemoSongs.all; return }
        do {
            songs = try await m.spotify?.tracks(playlistID: playlist.id) ?? []
            if songs.isEmpty { note = "This playlist is empty." }
        } catch SpotifyProvider.BrowseError.forbidden {
            note = "Spotify only lets Lunara list the songs of playlists you own. You can still play the whole playlist."
        } catch SpotifyProvider.BrowseError.needsReconnect {
            note = "Spotify needs a fresh sign-in. Go back and use Reconnect."
        } catch { message = "Couldn't load the songs. Check your connection." }
    }
    func play(_ s: SongItem) async {
        if demo { onPlayed(); return }
        if let e = await m.spotify?.play(uri: s.id, context: playlist.uri) { message = e } else { onPlayed() }
    }
    func playAll() async {
        if demo { onPlayed(); return }
        if let e = await m.spotify?.play(contextURI: playlist.uri) { message = e } else { onPlayed() }
    }
}

/// Tracks of one Apple Music library playlist or album.
struct AMTracksView: View {
    @ObservedObject var m: PlayerModel
    let item: AMItem
    var onPlayed: () -> Void
    @State private var songs: [SongItem] = []
    @State private var loading = true
    @State private var message: String?
    private var demo: Bool { CommandLine.arguments.contains("-demo") }

    var body: some View {
        List {
            Button { Task { await playAll() } } label: { Label(item.isAlbum ? "Play album" : "Play playlist", systemImage: "play.circle.fill") }
            if let message { Text(message).foregroundStyle(.orange) }
            if loading { ProgressView() }
            else if songs.isEmpty { Text("No songs found.").foregroundStyle(.secondary) }
            ForEach(songs) { s in
                Button { Task { await play(s) } } label: { SongRow(s: s) }.buttonStyle(.plain)
            }
        }
        .navigationTitle(item.name).navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    func load() async {
        defer { loading = false }
        if demo { songs = DemoSongs.all; return }
        do { songs = try await m.appleMusic?.tracks(of: item) ?? [] }
        catch { message = "Couldn't load the songs: \(error.localizedDescription)" }
    }
    func play(_ s: SongItem) async {
        if demo { onPlayed(); return }
        if let e = await m.appleMusic?.play(songID: s.id, fromList: true) { message = e } else { onPlayed() }
    }
    func playAll() async {
        if demo { onPlayed(); return }
        if let e = await m.appleMusic?.play(item) { message = e } else { onPlayed() }
    }
}

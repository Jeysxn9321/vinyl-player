import SwiftUI

/// Spotify playlist browser: searchable grid of covers, tap to play. Playlist tracks are not listed
/// (Spotify's Feb 2026 dev-mode rules only allow that for playlists you own).
struct PlaylistsView: View {
    @ObservedObject var m: PlayerModel
    @Environment(\.dismiss) private var dismiss
    @State private var items: [SpotifyProvider.Playlist] = []
    @State private var query = ""
    @State private var loading = true
    @State private var needsReconnect = false
    @State private var message: String?

    private var shown: [SpotifyProvider.Playlist] {
        query.isEmpty ? items : items.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }
    private var demo: Bool { CommandLine.arguments.contains("-demo") }

    var body: some View {
        NavigationStack {
            ScrollView {
                if loading { ProgressView().padding(.top, 60) }
                else if needsReconnect {
                    VStack(spacing: 14) {
                        Text("Lunara needs permission to read your playlists.").multilineTextAlignment(.center)
                        Button("Reconnect Spotify") { Task { await m.reconnectSpotify(); dismiss() } }.buttonStyle(.borderedProminent)
                    }.padding(30)
                } else if shown.isEmpty {
                    Text(items.isEmpty ? "No playlists found." : "No match.").foregroundStyle(.secondary).padding(.top, 60)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 18) {
                        ForEach(shown) { p in
                            Button { Task { await play(p) } } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    AsyncImage(url: p.imageURL) { $0.resizable().scaledToFill() } placeholder: { Color(white: 0.2) }
                                        .aspectRatio(1, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 8))
                                    Text(p.name).font(.footnote.weight(.semibold)).lineLimit(1)
                                    if !p.owner.isEmpty { Text(p.owner).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                                }.foregroundStyle(.white)
                            }.buttonStyle(.plain)
                        }
                    }.padding(16)
                }
                if let message { Text(message).font(.footnote).foregroundStyle(.orange).padding() }
            }
            .searchable(text: $query, prompt: "Search playlists")
            .navigationTitle("Playlists")
            .toolbar { Button("Done") { dismiss() } }
            .task { await load() }
        }
        .preferredColorScheme(.dark)
    }

    func load() async {
        defer { loading = false }
        if demo {
            items = ["Liked Mix", "Late Night Drive", "Archivos Eladio", "Bad Bunny Essentials", "Chill Sunday", "Top Songs 2026"]
                .enumerated().map { .init(id: "\($0.offset)", name: $0.element, owner: "Demo", uri: "spotify:playlist:\($0.offset)", imageURL: nil) }
            return
        }
        do { items = try await m.spotify?.playlists() ?? [] }
        catch SpotifyProvider.BrowseError.needsReconnect { needsReconnect = true }
        catch { message = "Couldn't load playlists. Check your connection." }
    }

    func play(_ p: SpotifyProvider.Playlist) async {
        if demo { dismiss(); return }
        if let e = await m.spotify?.play(contextURI: p.uri) { message = e } else { dismiss() }
    }
}

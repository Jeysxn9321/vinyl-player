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
                        Button("Reconnect Spotify") {
                            Task {
                                if await m.reauthorizeSpotify() { needsReconnect = false; loading = true; await load() }
                                else { message = "Sign-in was cancelled. Your existing login is unchanged." }
                            }
                        }.buttonStyle(.borderedProminent)
                    }.padding(30)
                } else if shown.isEmpty {
                    Text(items.isEmpty ? "No playlists found." : "No match.").foregroundStyle(.secondary).padding(.top, 60)
                } else {
                    LazyVStack(spacing: -70) {
                        ForEach(shown) { p in
                            Button { Task { await play(p) } } label: { cover(p) }
                                .buttonStyle(.plain)
                                .scrollTransition(axis: .vertical) { content, phase in
                                    content
                                        .rotation3DEffect(.degrees(phase.value * -38), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
                                        .scaleEffect(1 - abs(phase.value) * 0.18)
                                        .opacity(1 - abs(phase.value) * 0.45)
                                }
                        }
                    }
                    .padding(.vertical, 40).padding(.horizontal, 24)
                    .frame(maxWidth: 380).frame(maxWidth: .infinity)
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

    /// Square cover with the name over a bottom gradient; a colour derived from the name when there is no image.
    func cover(_ p: SpotifyProvider.Playlist) -> some View {
        let hue = Double(p.name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 360 }) / 360
        let fallback = LinearGradient(colors: [Color(hue: hue, saturation: 0.6, brightness: 0.75),
                                               Color(hue: hue, saturation: 0.8, brightness: 0.35)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing)
        return AsyncImage(url: p.imageURL) { $0.resizable().scaledToFill() } placeholder: { fallback }
            .aspectRatio(1, contentMode: .fit)
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.name).font(.headline).lineLimit(2)
                    if !p.owner.isEmpty { Text(p.owner).font(.caption).opacity(0.75).lineLimit(1) }
                }
                .foregroundStyle(.white).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom))
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.5), radius: 12, y: 6)
            .contentShape(RoundedRectangle(cornerRadius: 14))
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

import SwiftUI
import MediaPlayer

/// "Save" and "Add to playlist" for the song that is playing.
/// Apple Music has no public "favourite" call: the closest real action is adding the song to the library, which is what we do
/// (and the button says so). Spotify: Liked Songs through PUT /me/library, playlists through POST /playlists/{id}/items.
/// Both need permissions the first Lunara builds did not ask for, so an old Spotify login must reconnect once.
enum TrackActions {
    static func isStoreID(_ s: String) -> Bool { !s.isEmpty && s.allSatisfy(\.isNumber) }
    /// Spotify track IDs are 22 base-62 characters; local files fall back to "title|artist" and have no URI.
    static func spotifyURI(_ id: String) -> String? {
        id.count == 22 && id.allSatisfy({ $0.isLetter || $0.isNumber }) ? "spotify:track:" + id : nil
    }

    private static func authorized() async -> Bool {
        if MPMediaLibrary.authorizationStatus() == .notDetermined {
            _ = await withCheckedContinuation { c in MPMediaLibrary.requestAuthorization { c.resume(returning: $0) } }
        }
        return MPMediaLibrary.authorizationStatus() == .authorized
    }

    static func addToAppleLibrary(_ id: String) async -> String? {
        guard isStoreID(id) else { return "This song has no Apple Music store ID (it may already be a library item)." }
        guard await authorized() else { return "Allow Media & Apple Music access in Settings to add songs." }
        return await withCheckedContinuation { c in
            MPMediaLibrary.default().addItem(withProductID: id) { _, e in
                c.resume(returning: e.map { "Apple Music refused: \($0.localizedDescription)" })
            }
        }
    }

    /// Apple Music only lets an app write to playlists it created, so songs go to one playlist named "Lunara".
    static let applePlaylistID = UUID(uuidString: "5C7E2A52-0D6B-4E8E-9F0B-4C0A1E7A1A11")!
    static func addToAppleLunaraPlaylist(_ id: String) async -> String? {
        guard isStoreID(id) else { return "This song has no Apple Music store ID." }
        guard await authorized() else { return "Allow Media & Apple Music access in Settings to add songs." }
        return await withCheckedContinuation { c in
            let meta = MPMediaPlaylistCreationMetadata(name: "Lunara")
            MPMediaLibrary.default().getPlaylist(with: applePlaylistID, creationMetadata: meta) { pl, e in
                guard let pl else { c.resume(returning: "Couldn't open the Lunara playlist: \(e?.localizedDescription ?? "unknown error")"); return }
                pl.addItem(withProductID: id) { e2 in c.resume(returning: e2.map { "Apple Music refused: \($0.localizedDescription)" }) }
            }
        }
    }
}

struct AddToPlaylistView: View {
    @ObservedObject var m: PlayerModel
    let trackID: String
    @Environment(\.dismiss) private var dismiss
    @State private var playlists: [SpotifyProvider.Playlist] = []
    @State private var loading = true
    @State private var message: String?
    @State private var reconnect = false

    var body: some View {
        NavigationStack {
            List {
                if let message { Text(message).foregroundStyle(.orange) }
                if reconnect {
                    Button("Reconnect Spotify (adds the permission to edit playlists)") {
                        Task { if await m.reauthorizeSpotify() { reconnect = false; message = nil; await load() } }
                    }
                }
                if m.provider?.kind == .spotify {
                    if loading { ProgressView() }
                    ForEach(playlists) { p in
                        Button { Task { await add(p) } } label: {
                            VStack(alignment: .leading) { Text(p.name); Text(p.owner).font(.caption).foregroundStyle(.secondary) }
                        }.buttonStyle(.plain)
                    }
                } else {
                    Button { Task { await addApple() } } label: {
                        VStack(alignment: .leading) {
                            Text("Lunara playlist")
                            Text("Created in your Apple Music library the first time. Apple only lets an app edit playlists it made.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.buttonStyle(.plain)
                }
            }
            .navigationTitle("Add to playlist")
            .toolbar { Button("Cancel") { dismiss() } }
            .task { await load() }
        }.preferredColorScheme(.dark)
    }

    func load() async {
        guard let sp = m.spotify else { loading = false; return }
        do { playlists = try await sp.playlists() }
        catch SpotifyProvider.BrowseError.needsReconnect { reconnect = true; message = "Spotify needs to be reconnected." }
        catch { message = "Couldn't load your playlists." }
        loading = false
    }

    func add(_ p: SpotifyProvider.Playlist) async {
        guard let uri = TrackActions.spotifyURI(trackID) else { message = "This item has no Spotify track ID (local file?)."; return }
        if let e = await m.spotify?.add(uri: uri, toPlaylist: p.id) {
            message = e; reconnect = e.contains("Reconnect")
        } else { m.flash("Added to \(p.name)"); dismiss() }
    }

    func addApple() async {
        if let e = await TrackActions.addToAppleLunaraPlaylist(trackID) { message = e }
        else { m.flash("Added to the Lunara playlist"); dismiss() }
    }
}

import Foundation
import MusicKit

/// One row in the Apple Music library browser.
struct AMItem: Identifiable, Hashable {
    var id: String
    var name: String
    var subtitle: String
    var imageURL: URL?
    var isAlbum: Bool
}

/// Controls the app's own ApplicationMusicPlayer. MusicKit does not expose the
/// system Music app's playback to third parties, so playback must start in this app.
final class AppleMusicProvider: MusicProvider {
    let kind = ProviderKind.appleMusic
    var onState: ((MusicState) -> Void)?
    private let player = ApplicationMusicPlayer.shared
    private var timer: Timer?
    private var playlists: [String: Playlist] = [:]
    private var albums: [String: Album] = [:]

    func authorize() async throws {
        let s = await MusicAuthorization.request()
        guard s == .authorized else { throw MusicError.denied }
        await MainActor.run { startPolling() }
    }
    func disconnect() { timer?.invalidate(); player.stop(); onState?(MusicState()) }

    func play() async { try? await player.play(); publish() }
    func pause() async { player.pause(); publish() }
    func next() async { try? await player.skipToNextEntry(); publish() }
    func previous() async { try? await player.skipToPreviousEntry(); publish() }
    func seek(to t: TimeInterval) async { player.playbackTime = t; publish() }

    /// Library playlists and albums (needs an Apple Music library; empty without one).
    func library() async throws -> [AMItem] {
        var pReq = MusicLibraryRequest<Playlist>()
        pReq.limit = 50
        let pRes = try await pReq.response()
        var aReq = MusicLibraryRequest<Album>()
        aReq.limit = 50
        let aRes = try await aReq.response()
        playlists = [:]; albums = [:]
        var out: [AMItem] = []
        for p in pRes.items {
            playlists[p.id.rawValue] = p
            out.append(AMItem(id: p.id.rawValue, name: p.name, subtitle: "Playlist",
                              imageURL: p.artwork?.url(width: 600, height: 600), isAlbum: false))
        }
        for a in aRes.items {
            albums[a.id.rawValue] = a
            out.append(AMItem(id: a.id.rawValue, name: a.title, subtitle: a.artistName,
                              imageURL: a.artwork?.url(width: 600, height: 600), isAlbum: true))
        }
        return out
    }

    /// Starts playback of a library item. Returns an error message, or nil on success.
    func play(_ item: AMItem) async -> String? {
        do {
            if item.isAlbum, let a = albums[item.id] { player.queue = ApplicationMusicPlayer.Queue(for: [a]) }
            else if let p = playlists[item.id] { player.queue = ApplicationMusicPlayer.Queue(for: [p]) }
            else { return "That item is no longer available. Reopen the library." }
            try await player.play()
            publish()
            return nil
        } catch {
            return "Couldn't start playback: \(error.localizedDescription)"
        }
    }

    private func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.publish() }
    }

    private func publish() {
        var st = MusicState(provider: .appleMusic)
        st.isPlaying = player.state.playbackStatus == .playing
        st.progress = player.playbackTime
        if let entry = player.queue.currentEntry {
            if case .song(let song)? = entry.item {
                st.track = Track(id: song.id.rawValue, title: song.title, artist: song.artistName,
                                 album: song.albumTitle ?? "",
                                 artworkURL: song.artwork?.url(width: 1200, height: 1200),
                                 duration: song.duration ?? 0)
            } else {
                // Entry not resolved to a song yet: show what the queue knows so the record is not blank.
                st.track = Track(id: entry.id, title: entry.title, artist: entry.subtitle ?? "", album: "",
                                 artworkURL: entry.artwork?.url(width: 1200, height: 1200), duration: 0)
            }
        }
        onState?(st)
    }
}

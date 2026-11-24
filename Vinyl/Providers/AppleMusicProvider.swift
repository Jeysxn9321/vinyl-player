import Foundation
import MusicKit

/// Controls the app's own ApplicationMusicPlayer. MusicKit does not expose the
/// system Music app's playback to third parties, so playback must start in this app.
final class AppleMusicProvider: MusicProvider {
    let kind = ProviderKind.appleMusic
    var onState: ((MusicState) -> Void)?
    private let player = ApplicationMusicPlayer.shared
    private var timer: Timer?

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

    private func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.publish() }
    }

    private func publish() {
        var st = MusicState(provider: .appleMusic)
        st.isPlaying = player.state.playbackStatus == .playing
        st.progress = player.playbackTime
        if let entry = player.queue.currentEntry, case .song(let song)? = entry.item {
            st.track = Track(id: song.id.rawValue, title: song.title, artist: song.artistName,
                             album: song.albumTitle ?? "",
                             artworkURL: song.artwork?.url(width: 1200, height: 1200),
                             duration: song.duration ?? 0)
        }
        onState?(st)
    }
}

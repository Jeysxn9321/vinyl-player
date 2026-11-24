import Foundation
import UIKit

enum ProviderKind: String, Codable { case spotify, appleMusic }

struct Track: Equatable {
    var id: String
    var title: String
    var artist: String
    var album: String
    var artworkURL: URL?
    var duration: TimeInterval
    /// Spotify only: used to open the exact artist/album. Other providers search by name.
    var artistID: String? = nil
    var albumID: String? = nil
}

enum RepeatMode: String { case off, all, one
    var next: RepeatMode { self == .off ? .all : (self == .all ? .one : .off) }
}

struct MusicState: Equatable {
    var shuffle = false
    var repeatMode = RepeatMode.off
    var track: Track?
    var isPlaying = false
    var progress: TimeInterval = 0
    var provider: ProviderKind?
}

protocol MusicProvider: AnyObject {
    var kind: ProviderKind { get }
    var onState: ((MusicState) -> Void)? { get set }
    func authorize() async throws
    func disconnect()
    func play() async
    func pause() async
    func next() async
    func previous() async
    func seek(to: TimeInterval) async
    func setShuffle(_ on: Bool) async
    func setRepeat(_ mode: RepeatMode) async
}

enum MusicError: LocalizedError {
    case denied, notConfigured(String)
    var errorDescription: String? {
        switch self {
        case .denied: return "Access was denied."
        case .notConfigured(let s): return s
        }
    }
}

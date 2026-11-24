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
}

struct MusicState: Equatable {
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

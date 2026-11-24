import Foundation

/// What a piece of artwork is. Only `.vinylLabel`, `.sideA` and `.sideB` are ever described as a disc label,
/// and only when the source tagged the image as one (see `Verification`).
enum ArtworkKind: String, Codable {
    case streaming       // the cover Spotify / Apple Music give us
    case vinylLabel      // centre label of a physical vinyl release
    case sideA, sideB    // label of one side, when the source says so
    case edition         // cover or product photo of a vinyl edition (not a label)
    case custom          // the user's own image

    var title: String {
        switch self {
        case .streaming: return "Streaming cover"
        case .vinylLabel: return "Vinyl label"
        case .sideA: return "Side A label"
        case .sideB: return "Side B label"
        case .edition: return "Edition artwork"
        case .custom: return "Your artwork"
        }
    }
}

/// How much we can honestly claim about an image. Never upgraded by guesswork.
enum Verification: String, Codable {
    case streaming        // the streaming service's own cover
    case tagged           // the source (community-edited database) tags this image as a disc label of a matching vinyl release
    case unverified       // belongs to a matching vinyl release, but nothing says it is a label
    case user             // uploaded by the user

    var badge: String {
        switch self {
        case .streaming: return "Streaming"
        case .tagged: return "Tagged as vinyl label"
        case .unverified: return "Not verified as label"
        case .user: return "Yours"
        }
    }
}

enum ArtworkSource: String, Codable {
    case streaming, musicBrainz, discogs, user
    var title: String {
        switch self {
        case .streaming: return "Streaming service"
        case .musicBrainz: return "MusicBrainz + Cover Art Archive"
        case .discogs: return "Discogs"
        case .user: return "You"
        }
    }
}

/// One selectable piece of artwork for the current album.
struct ArtworkVariant: Identifiable, Codable, Equatable {
    var id: String                 // stable: "caa:<imageID>", "discogs:<imageID>", "custom:<uuid>", "streaming"
    var kind: ArtworkKind
    var verification: Verification
    var source: ArtworkSource
    var imageURL: URL?             // https only; nil for streaming / custom
    var fullURL: URL? = nil
    var releaseID: String? = nil   // MusicBrainz release MBID (or Discogs release id) — the edition this belongs to
    var editionTitle: String? = nil
    var year: String? = nil
    var format: String? = nil      // e.g. `12" Vinyl`, only what the database says
    var catalogNumber: String? = nil
    var country: String? = nil
    var confidence: Double = 0     // 0...1, how sure we are the RELEASE matches the album. Not "is a label".
    var detail: String? = nil      // image comment from the database, e.g. "Side A"
    var sourceURL: URL? = nil      // page of the release at the source, for attribution
    var localFile: String? = nil   // file name inside the custom folder, for `.custom`

    static let streamingID = "streaming"
    static var streaming: ArtworkVariant {
        ArtworkVariant(id: streamingID, kind: .streaming, verification: .streaming, source: .streaming)
    }
}

/// What the player knows about the album that is playing. Optional fields stay nil until a provider can supply them.
struct AlbumQuery: Equatable {
    var artist: String
    var album: String
    var year: String? = nil        // not provided by the current providers yet
    var barcode: String? = nil     // UPC/EAN; same
    var releaseMBID: String? = nil // same

    /// Stable per-album key: normalized artist + full album title. Streaming services give separate titles to
    /// deluxe / anniversary editions, so those editions get separate keys.
    var key: String { Matching.normalize(artist) + "|" + Matching.normalize(album) }
}

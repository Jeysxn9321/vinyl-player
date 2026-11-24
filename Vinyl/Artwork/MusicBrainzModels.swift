import Foundation

// Decodable shapes of the MusicBrainz web service (fmt=json) and Cover Art Archive index.json,
// written against recorded real responses (see VinylTests/Fixtures).

struct MBReleaseGroupSearch: Decodable {
    var releaseGroups: [MBReleaseGroup]
    enum CodingKeys: String, CodingKey { case releaseGroups = "release-groups" }
}

struct MBReleaseGroup: Decodable {
    var id: String
    var title: String
    var score: Int?
    var firstReleaseDate: String?
    var artistCredit: [Credit]?
    struct Credit: Decodable { var name: String }
    var artistName: String { (artistCredit ?? []).map(\.name).joined(separator: " ") }
    enum CodingKeys: String, CodingKey {
        case id, title, score
        case firstReleaseDate = "first-release-date", artistCredit = "artist-credit"
    }
}

struct MBReleaseList: Decodable { var releases: [MBRelease] }

struct MBRelease: Decodable {
    var id: String
    var title: String
    var date: String?
    var country: String?
    var barcode: String?
    var disambiguation: String?
    var media: [Medium]
    var labelInfo: [LabelInfo]?
    var coverArt: CoverArtFlags?
    struct Medium: Decodable { var format: String? }
    struct LabelInfo: Decodable {
        var catalogNumber: String?
        enum CodingKeys: String, CodingKey { case catalogNumber = "catalog-number" }
    }
    struct CoverArtFlags: Decodable { var artwork: Bool? }
    enum CodingKeys: String, CodingKey {
        case id, title, date, country, barcode, disambiguation, media
        case labelInfo = "label-info", coverArt = "cover-art-archive"
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        date = try? c.decode(String.self, forKey: .date)
        country = try? c.decode(String.self, forKey: .country)
        barcode = try? c.decode(String.self, forKey: .barcode)
        disambiguation = try? c.decode(String.self, forKey: .disambiguation)
        media = (try? c.decode([Medium].self, forKey: .media)) ?? []
        labelInfo = try? c.decode([LabelInfo].self, forKey: .labelInfo)
        coverArt = try? c.decode(CoverArtFlags.self, forKey: .coverArt)
    }
}

struct CAAIndex: Decodable {
    var images: [Image]
    struct Image: Decodable {
        var id: Int64
        var types: [String]
        var approved: Bool
        var image: String
        var comment: String?
        var thumbnails: [String: String]?
        enum K: String, CodingKey { case id, types, approved, image, comment, thumbnails }
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: K.self)
            // `id` is a number in recent data; tolerate a string.
            if let n = try? c.decode(Int64.self, forKey: .id) { id = n }
            else { id = Int64((try? c.decode(String.self, forKey: .id)) ?? "") ?? 0 }
            types = (try? c.decode([String].self, forKey: .types)) ?? []
            approved = (try? c.decode(Bool.self, forKey: .approved)) ?? false
            image = try c.decode(String.self, forKey: .image)
            comment = try? c.decode(String.self, forKey: .comment)
            thumbnails = try? c.decode([String: String].self, forKey: .thumbnails)
        }
    }
}

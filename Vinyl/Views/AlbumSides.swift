import Foundation

/// Neither Apple Music, Spotify nor iTunes Search say how a vinyl pressing divides its tracks, so this is an ESTIMATE:
/// the album is cut in two by track count (side A gets the extra song when odd). Real pressings differ; the UI says so.
enum AlbumSides {
    static func split<T>(_ items: [T]) -> (a: [T], b: [T]) {
        let cut = (items.count + 1) / 2
        return (Array(items[..<cut]), Array(items[cut...]))
    }
}

import Foundation
import CryptoKit
import UIKit

/// Disk persistence: image + metadata caches (purgeable, in Caches) and the user's choices / uploads (Application Support).
enum ArtworkStore {
    private static let fm = FileManager.default
    private static func dir(_ base: FileManager.SearchPathDirectory, _ name: String) -> URL {
        let u = fm.urls(for: base, in: .userDomainMask)[0].appendingPathComponent("Lunara/\(name)", isDirectory: true)
        try? fm.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    static var cacheDir: URL { dir(.cachesDirectory, "art") }
    static var supportDir: URL { dir(.applicationSupportDirectory, "art") }
    static var customDir: URL { dir(.applicationSupportDirectory, "custom") }

    static func hash(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: metadata cache
    private struct Meta: Codable { var date: Date; var variants: [ArtworkVariant] }
    static let metaTTL: TimeInterval = 14 * 86400

    static func cachedVariants(_ key: String) -> [ArtworkVariant]? {
        let f = cacheDir.appendingPathComponent("meta-\(hash(key)).json")
        guard let d = try? Data(contentsOf: f), let m = try? JSONDecoder().decode(Meta.self, from: d),
              Date().timeIntervalSince(m.date) < metaTTL else { return nil }
        return m.variants
    }
    static func saveVariants(_ v: [ArtworkVariant], key: String) {
        let f = cacheDir.appendingPathComponent("meta-\(hash(key)).json")
        if let d = try? JSONEncoder().encode(Meta(date: Date(), variants: v)) { try? d.write(to: f, options: .atomic) }
    }

    // MARK: image cache
    /// Bytes of an image, from disk when cached. Throws on network failure; the caller decides what to show.
    static func imageData(_ url: URL) async throws -> Data {
        let f = cacheDir.appendingPathComponent("img-\(hash(url.absoluteString))")
        if let d = try? Data(contentsOf: f) { return d }
        var r = URLRequest(url: url); r.setValue(ArtworkNet.userAgent, forHTTPHeaderField: "User-Agent")
        let (d, resp) = try await ArtworkNet.session.data(for: r)
        guard (resp as? HTTPURLResponse)?.statusCode == 200, UIImage(data: d) != nil else { throw ArtworkError.http((resp as? HTTPURLResponse)?.statusCode ?? 0) }
        try? d.write(to: f, options: .atomic)
        return d
    }
    static func image(for v: ArtworkVariant) async -> UIImage? {
        if v.kind == .custom, let n = v.localFile { return UIImage(contentsOfFile: customDir.appendingPathComponent(n).path) }
        guard let u = v.imageURL, let d = try? await imageData(u) else { return nil }
        return UIImage(data: d)
    }

    // MARK: choices (per album key)
    private static var selFile: URL { supportDir.appendingPathComponent("selection.json") }
    private static var customFile: URL { supportDir.appendingPathComponent("customs.json") }

    static func defaults() -> [String: ArtworkVariant] {
        (try? Data(contentsOf: selFile)).flatMap { try? JSONDecoder().decode([String: ArtworkVariant].self, from: $0) } ?? [:]
    }
    static func setDefault(_ v: ArtworkVariant?, key: String) {
        var all = defaults()
        all[key] = v
        if let d = try? JSONEncoder().encode(all) { try? d.write(to: selFile, options: .atomic) }
    }

    // MARK: user uploads
    static func customs() -> [String: [ArtworkVariant]] {
        (try? Data(contentsOf: customFile)).flatMap { try? JSONDecoder().decode([String: [ArtworkVariant]].self, from: $0) } ?? [:]
    }
    static func addCustom(_ image: UIImage, key: String) -> ArtworkVariant? {
        // Centre-crop to a square and cap the size so any resolution fits the label cheaply.
        let side = min(image.size.width, image.size.height)
        guard side > 0 else { return nil }
        let out = min(side, 1024)
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let sq = UIGraphicsImageRenderer(size: CGSize(width: out, height: out), format: fmt).image { _ in
            let k = out / side
            image.draw(in: CGRect(x: -(image.size.width - side) / 2 * k, y: -(image.size.height - side) / 2 * k,
                                  width: image.size.width * k, height: image.size.height * k))
        }
        guard let d = sq.jpegData(compressionQuality: 0.9) else { return nil }
        let id = UUID().uuidString, name = "\(id).jpg"
        guard (try? d.write(to: customDir.appendingPathComponent(name), options: .atomic)) != nil else { return nil }
        let v = ArtworkVariant(id: "custom:\(id)", kind: .custom, verification: .user, source: .user, localFile: name)
        var all = customs(); all[key, default: []].append(v)
        if let e = try? JSONEncoder().encode(all) { try? e.write(to: customFile, options: .atomic) }
        return v
    }
    static func removeCustom(_ v: ArtworkVariant, key: String) {
        if let n = v.localFile { try? fm.removeItem(at: customDir.appendingPathComponent(n)) }
        var all = customs(); all[key]?.removeAll { $0.id == v.id }
        if let e = try? JSONEncoder().encode(all) { try? e.write(to: customFile, options: .atomic) }
    }
}

import SwiftUI
import Security

/// Folder shared between the app and the widget extension (App Group container).
/// AltStore re-signs the app and rewrites the App Group ID (it adds the Apple team ID), so the declared ID may not be
/// the real one. We try the likely spellings and use the first one the system actually grants a container for.
/// If none works (no entitlement) `root` is nil and the widgets can only show their empty state: the app says so in Settings.
enum SharedStore {
    static let declared = "group.com.example.vinyl"

    /// Team ID of the signing identity, read from the keychain access group the system assigns to this process.
    static var teamID: String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: "lunara.teamid",
                                kSecAttrService as String: "lunara", kSecReturnAttributes as String: true]
        var out: AnyObject?
        var st = SecItemCopyMatching(q as CFDictionary, &out)
        if st == errSecItemNotFound {
            var a = q; a.removeValue(forKey: kSecReturnAttributes as String)
            a[kSecValueData as String] = Data("x".utf8)
            st = SecItemAdd(a as CFDictionary, nil)
            if st == errSecSuccess || st == errSecDuplicateItem { st = SecItemCopyMatching(q as CFDictionary, &out) }
        }
        guard st == errSecSuccess, let d = out as? [String: Any], let g = d[kSecAttrAccessGroup as String] as? String else { return nil }
        let t = g.split(separator: ".").first.map(String.init)
        return (t?.count == 10) ? t : nil
    }

    /// Exact App Group IDs the signing profile granted, read from embedded.mobileprovision (present in sideloaded builds).
    static var profileGroups: [String] {
        guard let u = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let d = try? Data(contentsOf: u),
              let a = d.range(of: Data("<?xml".utf8)), let b = d.range(of: Data("</plist>".utf8)),
              let plist = try? PropertyListSerialization.propertyList(from: d[a.lowerBound..<b.upperBound], format: nil) as? [String: Any],
              let ent = plist["Entitlements"] as? [String: Any] else { return [] }
        return (ent["com.apple.security.application-groups"] as? [String]) ?? []
    }

    static var candidates: [String] {
        var c: [String] = profileGroups
        if let alt = (Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String])?.first { c.append(alt) }
        c.append(declared)
        if let t = teamID {
            c.append("group.\(t).com.example.vinyl")
            c.append("\(declared).\(t)")
            c.append("group.\(t).\(declared)")
        }
        var seen = Set<String>()
        return c.filter { seen.insert($0).inserted }
    }

    static let root: URL? = {
        for g in candidates {
            if let u = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: g) { return u }
        }
        return nil
    }()

    static var available: Bool { root != nil }

    /// Shown in Settings so a failure can be diagnosed without a Mac.
    static var report: String {
        "profile groups: \(profileGroups.isEmpty ? "none" : profileGroups.joined(separator: ", "))
team: \(teamID ?? "unknown")
tried: \(candidates.count)
using: \(root == nil ? "nothing" : (candidates.first { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil } ?? "?"))"
    }

    static func url(_ name: String) -> URL? { root?.appendingPathComponent(name) }
    static func read(_ name: String) -> Data? { url(name).flatMap { try? Data(contentsOf: $0) } }
    @discardableResult static func write(_ d: Data?, _ name: String) -> Bool {
        guard let u = url(name) else { return false }
        if let d { return (try? d.write(to: u, options: .atomic)) != nil }
        try? FileManager.default.removeItem(at: u); return true
    }
}

/// The records the user picked for the collection widgets.
struct CollectionItem: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var artist: String
    var imageFile: String?
}

enum CollectionStore {
    private static let file = "collection.json"
    static func items() -> [CollectionItem] {
        guard let d = SharedStore.read(file) else { return [] }
        return (try? JSONDecoder().decode([CollectionItem].self, from: d)) ?? []
    }
    private static func save(_ i: [CollectionItem]) -> Bool { SharedStore.write(try? JSONEncoder().encode(i), file) }

    /// Returns false when the shared folder is unavailable.
    @discardableResult static func add(title: String, artist: String, image: UIImage?) -> Bool {
        var all = items()
        let id = "\(artist)|\(title)".lowercased()
        if all.contains(where: { $0.id == id }) { return true }
        var name: String?
        if let image, let small = image.scaled(to: 360), let jpg = small.jpegData(compressionQuality: 0.82) {
            let n = "c\(abs(id.hashValue)).jpg"
            if SharedStore.write(jpg, n) { name = n }
        }
        all.append(CollectionItem(id: id, title: title, artist: artist, imageFile: name))
        return save(all)
    }
    static func remove(_ item: CollectionItem) {
        if let f = item.imageFile { SharedStore.write(nil, f) }
        _ = save(items().filter { $0.id != item.id })
    }
    static func image(_ item: CollectionItem) -> UIImage? {
        item.imageFile.flatMap { SharedStore.read($0) }.flatMap(UIImage.init(data:))
    }
}

extension UIImage {
    func scaled(to side: CGFloat) -> UIImage? {
        let k = min(1, side / max(size.width, size.height))
        let s = CGSize(width: size.width * k, height: size.height * k)
        return UIGraphicsImageRenderer(size: s).image { _ in draw(in: CGRect(origin: .zero, size: s)) }
    }
}

/// One record in the collection widgets: black vinyl with the artwork as the centre label.
struct CollectionDisc: View {
    var image: UIImage?
    var tint: Color = Color(white: 0.35)
    var body: some View {
        GeometryReader { g in
            let s = min(g.size.width, g.size.height)
            ZStack {
                Circle().fill(Color(white: 0.06))
                Circle().inset(by: s * 0.06).stroke(Color.white.opacity(0.07), lineWidth: 0.7)
                Circle().inset(by: s * 0.13).stroke(Color.white.opacity(0.06), lineWidth: 0.7)
                Circle().inset(by: s * 0.2).stroke(Color.white.opacity(0.05), lineWidth: 0.7)
                if let image {
                    Image(uiImage: image).resizable().scaledToFill().frame(width: s * 0.5, height: s * 0.5).clipShape(Circle())
                } else {
                    Circle().fill(tint.opacity(0.9)).frame(width: s * 0.5, height: s * 0.5)
                }
                Circle().fill(.black).frame(width: s * 0.05, height: s * 0.05)
            }.frame(width: s, height: s)
        }.aspectRatio(1, contentMode: .fit)
    }
}

/// Collection widget body. Small: one record. Medium: a row of up to 3 with titles. Large: grid of up to 6.
struct CollectionWidgetView: View {
    var items: [CollectionItem]
    var family: Family
    enum Family { case small, medium, large }

    var body: some View {
        if items.isEmpty {
            VStack(spacing: 6) {
                CollectionDisc(image: nil).frame(width: 54, height: 54)
                Text("Lunara collection").font(.footnote.bold())
                Text(SharedStore.available ? "Add records in Lunara > Settings." : "No shared storage with the app.").font(.caption2).foregroundStyle(.white.opacity(0.6)).multilineTextAlignment(.center)
            }.foregroundStyle(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch family {
            case .small: cell(items[0], caption: true)
            case .medium: HStack(spacing: 10) { ForEach(items.prefix(3)) { cell($0, caption: true) } }
            case .large:
                let rows = stride(from: 0, to: min(items.count, 6), by: 3).map { Array(items[$0..<min($0 + 3, min(items.count, 6))]) }
                VStack(spacing: 12) { ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                    HStack(spacing: 10) { ForEach(r) { cell($0, caption: true) } ; if r.count < 3 { Spacer(minLength: 0) } }
                } }
            }
        }
    }

    private func cell(_ i: CollectionItem, caption: Bool) -> some View {
        VStack(spacing: 4) {
            CollectionDisc(image: CollectionStore.image(i))
            if caption {
                Text(i.title).font(.caption2.bold()).lineLimit(1)
                if family != .small { Text(i.artist).font(.system(size: 9)).foregroundStyle(.white.opacity(0.6)).lineLimit(1) }
            }
        }.foregroundStyle(.white).frame(maxWidth: .infinity)
    }
}

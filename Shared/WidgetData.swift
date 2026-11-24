import SwiftUI

/// What the home-screen widget shows: the last track Lunara saw. Shared through an App Group, which only
/// works if the installed app actually carries the entitlement (unverified for AltStore installs). When the
/// data is missing the widget shows a static record, never an error.
struct WidgetSnapshot: Codable, Equatable {
    var title: String
    var artist: String
    var isPlaying: Bool
    var tintR: Double
    var tintG: Double
    var tintB: Double
    var tint: Color { Color(red: tintR, green: tintG, blue: tintB) }

    /// AltStore may rewrite the group ID; if it publishes the real one in `ALTAppGroups`, use that.
    static var groupID: String {
        (Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String])?.first ?? "group.com.example.vinyl"
    }
    private static let key = "widgetSnapshot"
    private static var store: UserDefaults? { UserDefaults(suiteName: groupID) }

    static func load() -> WidgetSnapshot? {
        guard let d = store?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: d)
    }
    static func save(_ s: WidgetSnapshot?) {
        guard let store else { return }
        if let s, let d = try? JSONEncoder().encode(s) { store.set(d, forKey: key) } else { store.removeObject(forKey: key) }
    }
}

/// Widget body, also rendered inside the app under `-widget` for a CI screenshot.
struct RecordWidgetView: View {
    var snap: WidgetSnapshot?
    var wide: Bool
    var body: some View {
        HStack(spacing: 14) {
            RecordGlyph(tint: snap?.tint ?? Color(white: 0.35))
                .frame(width: wide ? 96 : 64, height: wide ? 96 : 64)
            if wide || snap == nil { text }
            if !wide && snap != nil { Spacer(minLength: 0) }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .overlay(alignment: .bottomLeading) {
            if !wide, let s = snap {
                VStack(alignment: .leading, spacing: 1) {
                    Text(s.title).font(.footnote.bold()).lineLimit(1)
                    Text(s.artist).font(.caption2).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
                }
            }
        }
    }
    @ViewBuilder private var text: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let s = snap {
                Text("LAST PLAYED").font(.caption2.weight(.semibold)).foregroundStyle(.white.opacity(0.5))
                Text(s.title).font(.headline).lineLimit(2)
                Text(s.artist).font(.subheadline).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
            } else {
                Text("Lunara").font(.headline)
                Text("Play something to fill this widget.").font(.caption).foregroundStyle(.white.opacity(0.65))
            }
        }
    }
}

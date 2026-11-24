import SwiftUI

enum Pref {
    static let autoHide = "autoHideControls"
    static let tint = "tintVinyl"
    static let lastProvider = "lastProvider"
    static let vinylColor = "vinylColor"
}

/// Record colour presets. "auto" follows the artwork tint.
enum VinylColor: String, CaseIterable {
    case auto, black, gold, white, blue, red
    var color: Color? {
        switch self {
        case .auto: return nil
        case .black: return Color(white: 0.05)
        case .gold: return Color(red: 0.55, green: 0.42, blue: 0.12)
        case .white: return Color(white: 0.82)
        case .blue: return Color(red: 0.1, green: 0.2, blue: 0.5)
        case .red: return Color(red: 0.55, green: 0.08, blue: 0.1)
        }
    }
}

struct SettingsView: View {
    @ObservedObject var m: PlayerModel
    @AppStorage(Pref.autoHide) private var autoHide = true
    @AppStorage(Pref.tint) private var tint = true
    @AppStorage(Pref.vinylColor) private var vinylColor = VinylColor.auto.rawValue
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Playback") {
                    LabeledContent("Source", value: m.provider?.kind == .spotify ? "Spotify" : "Apple Music")
                    Button("Disconnect", role: .destructive) { m.disconnect(); dismiss() }
                }
                Section("Appearance") {
                    Toggle("Hide controls automatically", isOn: $autoHide)
                    Toggle("Tint the record from the artwork", isOn: $tint)
                        .onChange(of: tint) { _, _ in m.retint() }
                }
                Section("Vinyl colour") {
                    HStack(spacing: 14) {
                        ForEach(VinylColor.allCases, id: \.self) { c in
                            Button { vinylColor = c.rawValue } label: {
                                ZStack {
                                    Circle().fill(c.color ?? Color.clear).frame(width: 34, height: 34)
                                    if c == .auto { Image(systemName: "wand.and.stars").foregroundStyle(.white) }
                                    Circle().stroke(vinylColor == c.rawValue ? Color.white : Color.white.opacity(0.25), lineWidth: vinylColor == c.rawValue ? 3 : 1)
                                        .frame(width: 38, height: 38)
                                }.frame(minWidth: 44, minHeight: 44)
                            }.buttonStyle(.plain).accessibilityLabel(c.rawValue.capitalized)
                        }
                    }
                }
                Section("About") {
                    Text("Spotify needs Premium and an active device. Apple Music plays only what you start in this app.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar { Button("Done") { dismiss() } }
        }
        .preferredColorScheme(.dark)
    }
}

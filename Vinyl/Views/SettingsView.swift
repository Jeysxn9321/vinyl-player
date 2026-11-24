import SwiftUI

enum Pref {
    static let autoHide = "autoHideControls"
    static let tint = "tintVinyl"
    static let lastProvider = "lastProvider"
}

struct SettingsView: View {
    @ObservedObject var m: PlayerModel
    @AppStorage(Pref.autoHide) private var autoHide = true
    @AppStorage(Pref.tint) private var tint = true
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

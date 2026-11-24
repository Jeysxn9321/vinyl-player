import SwiftUI
import WidgetKit

enum Pref {
    static let autoHide = "autoHideControls"
    static let tint = "tintVinyl"
    static let lastProvider = "lastProvider"
    static let vinylColor = "vinylColor"
    static let pattern = "vinylPattern"
    static let theme = "appTheme"
    static let fxSheen = "fxSheen"
    static let fxGlow = "fxGlow"
    static let fxDust = "fxDust"
    static let labelStyle = "labelStyle"
    static let labelSize = "labelSize"
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
    @AppStorage(Pref.pattern) private var pattern = VinylPattern.plain.rawValue
    @AppStorage(Pref.theme) private var theme = AppTheme.auto.rawValue
    @AppStorage(Pref.fxSheen) private var sheen = true
    @AppStorage(Pref.fxGlow) private var glow = false
    @AppStorage(Pref.fxDust) private var dust = false
    @AppStorage(Pref.labelStyle) private var labelStyle = LabelStyle.artwork.rawValue
    @AppStorage(Pref.labelSize) private var labelSize = LabelSize.medium.rawValue
    @AppStorage("art.auto") private var artAuto = true
    @AppStorage("art.discogsProxy") private var discogsProxy = ""
    @State private var discogsToken = ""
    @State private var discogsStatus: String?
    @State private var discogsBusy = false
    @State private var discogsConnected = DiscogsProvider.token != nil
    @State private var collection = CollectionStore.items()
    @Environment(\.openURL) private var openURL
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
                Section("Record pattern") {
                    Picker("Pattern", selection: $pattern) {
                        ForEach(VinylPattern.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                    }.pickerStyle(.segmented)
                }
                Section("Label") {
                    Picker("Style", selection: $labelStyle) {
                        ForEach(LabelStyle.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                    }.pickerStyle(.segmented)
                    Picker("Size", selection: $labelSize) {
                        ForEach(LabelSize.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                    }.pickerStyle(.segmented)
                }
                Section {
                    Toggle("Find vinyl artwork online", isOn: $artAuto)
                    if discogsConnected {
                        Label("Discogs connected", systemImage: "checkmark.seal")
                        Button("Disconnect Discogs", role: .destructive) {
                            Keychain.set(nil, DiscogsProvider.tokenKey); discogsConnected = false; discogsStatus = nil
                            NotificationCenter.default.post(name: .discogsChanged, object: nil)
                        }
                    } else {
                        Button { openURL(URL(string: "https://www.discogs.com/settings/developers")!) } label: {
                            Label("Open Discogs to get your token", systemImage: "safari")
                        }
                        SecureField("Paste your Discogs personal token", text: $discogsToken)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        Button(discogsBusy ? "Checking…" : "Connect Discogs") {
                            let t = discogsToken.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !t.isEmpty else { return }
                            discogsBusy = true; discogsStatus = nil
                            Task {
                                let err = await DiscogsProvider.checkToken(t)
                                discogsBusy = false
                                if let err { discogsStatus = err; return }
                                Keychain.set(t, DiscogsProvider.tokenKey); discogsToken = ""; discogsConnected = true
                                NotificationCenter.default.post(name: .discogsChanged, object: nil)
                            }
                        }.disabled(discogsBusy || discogsToken.trimmingCharacters(in: .whitespaces).isEmpty)
                        if let discogsStatus { Text(discogsStatus).foregroundStyle(.orange) }
                    }
                    TextField("Discogs proxy URL (optional)", text: $discogsProxy)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                } header: { Text("Vinyl artwork") } footer: {
                    Text("Looks up the album on MusicBrainz and the Cover Art Archive when a song plays. Discogs is off until you sign in at discogs.com, create a personal access token (Settings, Developers) and paste it here. The app ships no key: your token stays in this device's Keychain and is only sent to Discogs. Or use your own proxy (backend/discogs-proxy). Discogs images are never labelled as verified discs, and this has not been run against Discogs yet.")
                }
                Section {
                    if let t = m.state.track {
                        Button("Add “\(t.title)” to the collection") {
                            CollectionStore.add(title: t.title, artist: t.artist, image: m.discLabel)
                            collection = CollectionStore.items(); WidgetCenter.shared.reloadAllTimelines()
                        }
                    } else { Text("Play a record to add it here.").foregroundStyle(.secondary) }
                    ForEach(collection) { i in
                        VStack(alignment: .leading) { Text(i.title); Text(i.artist).font(.caption).foregroundStyle(.secondary) }
                    }.onDelete { idx in
                        idx.map { collection[$0] }.forEach(CollectionStore.remove)
                        collection = CollectionStore.items(); WidgetCenter.shared.reloadAllTimelines()
                    }
                    Text(SharedStore.available ? "Shared storage with the widgets: available." : "Shared storage with the widgets: NOT available on this install, so the widgets cannot show anything.")
                        .font(.caption).foregroundStyle(SharedStore.available ? Color.secondary : Color.orange)
                    Text(SharedStore.report).font(.caption2.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                } header: { Text("Widget collection") } footer: {
                    Text("The “Lunara collection” widget (small, medium, large) shows the records you add here. Not tested on a device yet.")
                }
                Section("Effects") {
                    Toggle("Light sheen", isOn: $sheen)
                    Toggle("Glow", isOn: $glow)
                    Toggle("Scratches and dust", isOn: $dust)
                }
                Section("Theme") {
                    Picker("Background", selection: $theme) {
                        ForEach(AppTheme.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
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

extension Notification.Name { static let discogsChanged = Notification.Name("lunara.discogsChanged") }

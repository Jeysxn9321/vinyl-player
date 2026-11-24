import SwiftUI
import PhotosUI

/// Frosted-lavender sheet to browse and choose the artwork shown on the record's centre label.
struct ArtworkSelectorView: View {
    @ObservedObject var art: ArtworkCenter
    var streamingCover: UIImage?
    @Environment(\.dismiss) private var dismiss
    @State private var picked: PhotosPickerItem?
    private let lavender = Color(red: 0.72, green: 0.66, blue: 1.0)

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                preview
                cards
                details
                actions
                Text(art.summary).font(.footnote).foregroundStyle(.white.opacity(0.6)).multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                if art.status == .loading { ProgressView().tint(lavender) }
                attribution
            }
            .padding(.vertical, 24)
        }
        .scrollIndicators(.hidden)
        .background(.ultraThinMaterial.opacity(0.9))
        .background(LinearGradient(colors: [lavender.opacity(0.28), Color(red: 0.08, green: 0.06, blue: 0.16)], startPoint: .top, endPoint: .bottom))
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.clear)
        .preferredColorScheme(.dark)
        .onChange(of: picked) { _, item in
            guard let item else { return }
            Task {
                if let d = try? await item.loadTransferable(type: Data.self), let i = UIImage(data: d) { art.addCustom(i) }
                picked = nil
            }
        }
    }

    private var header: some View {
        VStack(spacing: 2) {
            Text(art.query?.album ?? "Record").font(.headline).lineLimit(1)
            Text(art.query?.artist ?? "").font(.subheadline).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
        }.padding(.horizontal, 24)
    }

    private var preview: some View {
        ZStack {
            Circle().fill(Color.black)
            if let i = art.label ?? streamingCover {
                Image(uiImage: i).resizable().scaledToFill().frame(width: 130, height: 130).clipShape(Circle())
                    .id(ObjectIdentifier(i)).transition(.opacity)
            }
            Circle().fill(Color.black).frame(width: 12, height: 12)
        }
        .frame(width: 150, height: 150).overlay(Circle().stroke(lavender.opacity(0.5), lineWidth: 1.5))
        .shadow(color: lavender.opacity(0.35), radius: 18)
    }

    private var cards: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(art.variants) { v in
                    Button { art.show(v) } label: { card(v) }.buttonStyle(.plain)
                        .contextMenu { if v.kind == .custom { Button("Delete", systemImage: "trash", role: .destructive) { art.removeCustom(v) } } }
                }
            }.padding(.horizontal, 20)
        }
    }

    private func card(_ v: ArtworkVariant) -> some View {
        let on = art.current.id == v.id
        return VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08))
                if v.id == ArtworkVariant.streamingID {
                    if let s = streamingCover { Image(uiImage: s).resizable().scaledToFill() } else { Image(systemName: "music.note").foregroundStyle(.secondary) }
                } else if let t = art.thumbs[v.id] { Image(uiImage: t).resizable().scaledToFill() }
                else { ProgressView().controlSize(.small) }
            }
            .frame(width: 86, height: 86).clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(on ? lavender : .clear, lineWidth: 2))
            .overlay(alignment: .topTrailing) { if art.defaultID == v.id { Image(systemName: "star.fill").font(.caption2).padding(5).foregroundStyle(lavender) } }
            Text(v.kind.title).font(.caption2).lineLimit(1).frame(width: 86)
                .foregroundStyle(on ? .white : .white.opacity(0.6))
        }
    }

    private var details: some View {
        let v = art.current
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(v.kind.title).font(.subheadline.weight(.semibold))
                Spacer()
                Text(v.verification.badge).font(.caption2.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(v.verification == .tagged ? lavender.opacity(0.35) : Color.white.opacity(0.12)))
            }
            if v.source != .streaming && v.source != .user {
                row("Edition", [v.editionTitle, v.country].compactMap { $0 }.joined(separator: " · "))
                row("Year", v.year); row("Format", v.format); row("Catalogue no.", v.catalogNumber)
                row("Release match", "\(Int(v.confidence * 100))% (the release, not proof this is a label)")
            }
            row("Source", v.source.title)
            if let d = v.detail { row("Note", d) }
            if let u = v.sourceURL { Link("View release at source", destination: u).font(.caption) }
        }
        .font(.caption).padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.07)))
        .padding(.horizontal, 20)
    }
    @ViewBuilder private func row(_ k: String, _ v: String?) -> some View {
        if let v, !v.isEmpty { HStack(alignment: .top) { Text(k).foregroundStyle(.white.opacity(0.55)); Spacer(); Text(v).multilineTextAlignment(.trailing) } }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button { art.setDefault() } label: { pill(art.defaultID == art.current.id ? "Default ✓" : "Set as default", "star") }
                .disabled(art.current.id == ArtworkVariant.streamingID || art.defaultID == art.current.id)
            Button { art.resetToStreaming() } label: { pill("Reset", "arrow.uturn.backward") }
            PhotosPicker(selection: $picked, matching: .images) { pill("Upload", "photo") }
        }.padding(.horizontal, 20)
    }
    private func pill(_ t: String, _ icon: String) -> some View {
        Label(t, systemImage: icon).font(.footnote.weight(.semibold)).foregroundStyle(.white).lineLimit(1).frame(maxWidth: .infinity).padding(.vertical, 11)
            .background(Capsule().fill(lavender.opacity(0.22))).overlay(Capsule().stroke(lavender.opacity(0.4), lineWidth: 1))
    }

    private var attribution: some View {
        Text("Artwork data: MusicBrainz and the Cover Art Archive\(DiscogsProvider.configured != nil ? ", and Discogs" : "") (community-maintained; images remain the property of their rights holders). Images are matched automatically and may be wrong. Only images tagged as a disc by the database are called labels.")
            .font(.caption2).foregroundStyle(.white.opacity(0.4)).multilineTextAlignment(.center).padding(.horizontal, 28)
    }
}

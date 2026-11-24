import SwiftUI
import UIKit

/// Drives the label artwork for the album that is playing. Everything is async and best-effort: a failing provider
/// leaves the streaming cover on the disc and never touches playback.
@MainActor
final class ArtworkCenter: ObservableObject {
    enum Status: Equatable { case idle, loading, done, offline, disabled }

    @Published private(set) var variants: [ArtworkVariant] = [.streaming]
    @Published private(set) var current: ArtworkVariant = .streaming
    @Published private(set) var defaultID: String?
    @Published private(set) var status: Status = .idle
    @Published private(set) var label: UIImage?            // nil = use the streaming cover
    @Published private(set) var query: AlbumQuery?
    @Published private(set) var thumbs: [String: UIImage] = [:]

    private var task: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var providers: [ArtworkProvider] {
        var p: [ArtworkProvider] = [MusicBrainzProvider()]
        if let u = DiscogsProvider.configured { p.append(DiscogsProvider(proxy: u)) }
        return p
    }
    var auto: Bool { UserDefaults.standard.object(forKey: "art.auto") as? Bool ?? true }

    /// Call when the album changes. Cheap when nothing changed.
    func albumChanged(artist: String, album: String) {
        let q = AlbumQuery(artist: artist, album: album)
        guard q != query else { return }
        task?.cancel(); loadTask?.cancel()
        query = q; label = nil; current = .streaming; defaultID = nil; thumbs = [:]
        let customs = ArtworkStore.customs()[q.key] ?? []
        variants = [.streaming] + customs
        guard !album.isEmpty, !artist.isEmpty else { status = .idle; return }
        let saved = ArtworkStore.defaults()[q.key]
        if let saved { defaultID = saved.id; apply(saved) }          // the user's choice shows at once, even offline
        guard auto else { status = .disabled; return }
        status = .loading
        task = Task { [weak self] in await self?.discover(q, saved: saved, customs: customs) }
    }

    private func discover(_ q: AlbumQuery, saved: ArtworkVariant?, customs: [ArtworkVariant]) async {
        var found: [ArtworkVariant]
        if let c = ArtworkStore.cachedVariants(q.key) { found = c }
        else {
            found = []
            var failed = false
            for p in providers {
                do { found += try await p.variants(for: q) }
                catch is CancellationError { return }
                catch { failed = true }
            }
            if Task.isCancelled || q != query { return }
            // Cache only complete answers, so an outage is retried next time instead of remembered as "no vinyl".
            if failed { status = found.isEmpty ? .offline : .done } else { ArtworkStore.saveVariants(found, key: q.key) }
            if failed && found.isEmpty { variants = [.streaming] + customs; return }
        }
        guard q == query else { return }
        var seen = Set<String>()
        variants = ([.streaming] + customs + found).filter { seen.insert($0.id).inserted }
        status = .done
        if let saved, !variants.contains(where: { $0.id == saved.id }) { variants.insert(saved, at: 1) }
        // No saved choice (not even an explicit "streaming"): show the best tagged label, if any.
        if saved == nil, current.id == ArtworkVariant.streamingID, let best = Matching.autoPick(found) { show(best) }
        loadThumbs(q)
    }

    private func loadThumbs(_ q: AlbumQuery) {
        loadTask = Task { [weak self] in
            guard let self else { return }
            for v in self.variants where v.id != ArtworkVariant.streamingID {
                if Task.isCancelled || q != self.query { return }
                if self.thumbs[v.id] != nil { continue }
                if let img = await ArtworkStore.image(for: v) { self.thumbs[v.id] = img }
            }
        }
    }

    // MARK: choosing
    /// Show a variant on the disc (not remembered until `setDefault`).
    func show(_ v: ArtworkVariant) {
        current = v
        apply(v)
    }
    private func apply(_ v: ArtworkVariant) {
        current = v
        if v.id == ArtworkVariant.streamingID { withAnimation(.easeInOut(duration: 0.45)) { label = nil }; return }
        let q = query
        Task { [weak self] in
            let img = await ArtworkStore.image(for: v)
            guard let self, self.query == q, self.current.id == v.id else { return }
            withAnimation(.easeInOut(duration: 0.45)) { self.label = img }   // nil on failure -> streaming cover stays
        }
    }
    func cycle(_ step: Int) {
        guard variants.count > 1 else { return }
        let i = variants.firstIndex { $0.id == current.id } ?? 0
        show(variants[(i + step + variants.count) % variants.count])
    }
    func setDefault() {
        guard let q = query else { return }
        if current.id == ArtworkVariant.streamingID { resetToStreaming(); return }
        ArtworkStore.setDefault(current, key: q.key); defaultID = current.id
    }
    func resetToStreaming() {
        guard let q = query else { return }
        ArtworkStore.setDefault(.streaming, key: q.key); defaultID = ArtworkVariant.streamingID   // explicit: stays streaming next time
        show(.streaming)
    }
    func addCustom(_ image: UIImage) {
        guard let q = query, let v = ArtworkStore.addCustom(image, key: q.key) else { return }
        variants.append(v); thumbs[v.id] = UIImage(contentsOfFile: ArtworkStore.customDir.appendingPathComponent(v.localFile ?? "").path)
        show(v)
    }
    func removeCustom(_ v: ArtworkVariant) {
        guard let q = query, v.kind == .custom else { return }
        ArtworkStore.removeCustom(v, key: q.key)
        if defaultID == v.id { ArtworkStore.setDefault(nil, key: q.key); defaultID = nil }
        variants.removeAll { $0.id == v.id }
        if current.id == v.id { show(.streaming) }
    }

    /// One honest sentence for the selector.
    var summary: String {
        switch status {
        case .loading: return "Looking for vinyl artwork…"
        case .offline: return "Couldn't reach the artwork databases. The streaming cover stays."
        case .disabled: return "Automatic lookup is off in Settings."
        case .idle: return ""
        case .done:
            let labels = variants.filter { $0.verification == .tagged }.count
            let others = variants.filter { $0.source != .streaming && $0.source != .user && $0.verification == .unverified }.count
            if labels > 0 { return "\(labels) image\(labels == 1 ? "" : "s") tagged as vinyl labels by the community database." }
            if others > 0 { return "No verified vinyl label found. These images belong to vinyl editions but aren't confirmed labels." }
            return "No verified vinyl label found, so the streaming cover stays."
        }
    }
}

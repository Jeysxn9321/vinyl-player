import Foundation

/// Pure matching / classification logic. No network, no UI: everything here is unit-tested.
enum Matching {
    // MARK: text
    static func normalize(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en"))
        let mapped = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(mapped).split(separator: " ").joined(separator: " ")
    }

    /// Album title without edition decorations: "Album (Deluxe Edition)" / "Album - Remastered 2011" -> "Album".
    static func baseTitle(_ s: String) -> String {
        var t = s
        for pair in [("(", ")"), ("[", "]")] {
            while let o = t.range(of: pair.0), let c = t.range(of: pair.1, range: o.upperBound..<t.endIndex) {
                t.removeSubrange(o.lowerBound..<c.upperBound)
            }
        }
        if let r = t.range(of: " - ") { t = String(t[..<r.lowerBound]) }
        let out = t.trimmingCharacters(in: .whitespaces)
        return out.isEmpty ? s : out
    }

    /// 1 for equal, otherwise token overlap (Jaccard) of the normalized strings.
    static func similarity(_ a: String, _ b: String) -> Double {
        let x = normalize(a), y = normalize(b)
        if x.isEmpty || y.isEmpty { return 0 }
        if x == y { return 1 }
        let p = Set(x.split(separator: " ")), q = Set(y.split(separator: " "))
        return Double(p.intersection(q).count) / Double(p.union(q).count)
    }

    // MARK: release format
    static func isVinyl(_ formats: [String?]) -> Bool {
        formats.contains { ($0 ?? "").localizedCaseInsensitiveContains("vinyl") }
    }
    /// Short display string from what the database says (never invented): `12" Vinyl ×2`.
    static func formatSummary(_ formats: [String?]) -> String? {
        let f = formats.compactMap { $0 }.filter { !$0.isEmpty }
        guard let first = f.first else { return nil }
        if f.count > 1 && f.allSatisfy({ $0 == first }) { return "\(first) ×\(f.count)" }
        return Array(Set(f)).sorted().joined(separator: " + ")
    }

    // MARK: image classification (Cover Art Archive types)
    enum ImageClass: Equatable { case label, edition, skip }

    private static let notLabel: Set<String> = ["Front", "Back", "Booklet", "Tray", "Spine", "Poster", "Sticker", "Obi", "Liner",
                                                "Track", "Matrix/Runout", "Raw/Unedited", "Watermark", "Other"]
    /// `Medium` alone = an image of the disc itself. `Medium` plus Front/Booklet/Tray is usually a product photo
    /// of the whole package (seen in real data), so it is never treated as a label.
    static func classify(types: [String]) -> ImageClass {
        let t = Set(types)
        if t.contains("Medium") && t.isDisjoint(with: notLabel) { return .label }
        if t.contains("Medium") { return t.contains("Back") || t.contains("Matrix/Runout") ? .skip : .edition }
        if t == ["Front"] { return .edition }
        return .skip
    }

    static func sideKind(from comment: String?) -> ArtworkKind? {
        guard let c = comment?.lowercased(), !c.isEmpty else { return nil }
        if c.range(of: #"\b(side\s*(a|1|one)|a[- ]side)\b"#, options: .regularExpression) != nil { return .sideA }
        if c.range(of: #"\b(side\s*(b|2|two)|b[- ]side)\b"#, options: .regularExpression) != nil { return .sideB }
        return nil
    }

    static func secure(_ s: String?) -> URL? {
        guard let s, var c = URLComponents(string: s) else { return nil }
        if c.scheme == "http" { c.scheme = "https" }   // CAA still returns some http:// URLs; ATS would block them
        return c.scheme == "https" ? c.url : nil
    }

    // MARK: scoring
    /// Confidence that a release IS the album being played. Terms we have no input for are left out, not penalised.
    static func confidence(query: AlbumQuery, artist: String, title: String, isVinyl: Bool, date: String?, barcode: String?) -> Double {
        var sum = 0.0, weight = 0.0
        func add(_ w: Double, _ s: Double) { sum += w * s; weight += w }
        add(0.35, similarity(baseTitle(query.album), baseTitle(title)))
        add(0.30, similarity(query.artist, artist))
        add(0.10, isVinyl ? 1 : 0)
        if let y = query.year?.prefix(4), let d = date?.prefix(4), let a = Int(y), let b = Int(d) {
            add(0.10, a == b ? 1 : (abs(a - b) == 1 ? 0.5 : 0))
        }
        if let q = query.barcode, let b = barcode, !q.isEmpty, !b.isEmpty {
            let zeros = CharacterSet(charactersIn: "0")
            add(0.15, q.trimmingCharacters(in: zeros) == b.trimmingCharacters(in: zeros) ? 1 : 0)
        }
        return weight == 0 ? 0 : sum / weight
    }

    /// Best release-group for the query, or nil when nothing is close enough (never guess).
    static func pickGroup(_ groups: [MBReleaseGroup], query: AlbumQuery) -> MBReleaseGroup? {
        // Edition suffixes are ignored for eligibility, but an exact full-title match wins ("… (Vanderway Edit)" is a different album).
        let scored = groups.map { g -> (MBReleaseGroup, Double, Double, Double) in
            (g, similarity(baseTitle(query.album), baseTitle(g.title)), similarity(query.artist, g.artistName), similarity(query.album, g.title))
        }.filter { $0.1 >= 0.8 && $0.2 >= 0.7 }
        func rank(_ x: (MBReleaseGroup, Double, Double, Double)) -> Double { x.1 * 0.4 + x.3 * 0.3 + x.2 * 0.3 }
        return scored.max { rank($0) < rank($1) }?.0
    }

    /// Vinyl releases that have artwork, best first, capped so we do not hammer the Cover Art Archive.
    static func candidateReleases(_ releases: [MBRelease], group: MBReleaseGroup, query: AlbumQuery, limit: Int = 6) -> [(MBRelease, Double)] {
        let scored = releases.filter { isVinyl($0.media.map(\.format)) && ($0.coverArt?.artwork ?? false) }
            .map { r in (r, confidence(query: query, artist: group.artistName, title: r.title, isVinyl: true, date: r.date, barcode: r.barcode)) }
        let sorted = scored.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : ($0.0.date ?? "9") < ($1.0.date ?? "9") }
        return Array(sorted.prefix(limit))
    }

    /// Turn one release plus its Cover Art Archive index into selectable variants.
    static func variants(release r: MBRelease, group: MBReleaseGroup, index: CAAIndex, confidence c: Double, query: AlbumQuery) -> [ArtworkVariant] {
        let nameOK = similarity(baseTitle(query.album), baseTitle(r.title)) >= 0.8 && similarity(query.artist, group.artistName) >= 0.85
        return index.images.compactMap { img -> ArtworkVariant? in
            let cls = classify(types: img.types)
            guard cls != .skip, let thumb = secure(img.thumbnails?["500"] ?? img.thumbnails?["large"] ?? img.image) else { return nil }
            let sideK = sideKind(from: img.comment)
            let tagged = cls == .label && img.approved && nameOK
            let edition = [r.disambiguation, r.country].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            return ArtworkVariant(
                id: "caa:\(img.id)", kind: cls == .label ? (sideK ?? .vinylLabel) : .edition,
                verification: tagged ? .tagged : .unverified, source: .musicBrainz,
                imageURL: thumb, fullURL: secure(img.image), releaseID: r.id,
                editionTitle: edition.nilIfEmpty,
                year: r.date.map { String($0.prefix(4)) }, format: formatSummary(r.media.map(\.format)),
                catalogNumber: r.labelInfo?.compactMap(\.catalogNumber).first, country: r.country,
                confidence: c, detail: img.comment?.nilIfEmpty, sourceURL: URL(string: "https://musicbrainz.org/release/\(r.id)"))
        }
    }

    /// The variant shown automatically when the user has made no choice: the best community-tagged label, else nothing
    /// (unverified edition photos are never auto-applied, so the streaming cover stays).
    static func autoPick(_ ranked: [ArtworkVariant]) -> ArtworkVariant? {
        ranked.first { $0.verification == .tagged && $0.kind != .edition && $0.kind != .custom }
    }

    /// Order: tagged labels, then unverified, each by release confidence; duplicates (same image) dropped.
    static func rank(_ v: [ArtworkVariant]) -> [ArtworkVariant] {
        func tier(_ x: ArtworkVariant) -> Int { x.verification == .tagged ? 0 : (x.kind == .edition ? 2 : 1) }
        var seen = Set<String>()
        return v.sorted { tier($0) != tier($1) ? tier($0) < tier($1) : $0.confidence > $1.confidence }
            .filter { seen.insert($0.id).inserted }
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

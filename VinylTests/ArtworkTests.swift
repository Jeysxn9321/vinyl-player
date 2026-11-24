import XCTest
@testable import Vinyl

/// Parsing and scoring tests against real recorded MusicBrainz / Cover Art Archive responses (Fixtures/).
/// They test our logic only; they say nothing about the live services being reachable.
final class ArtworkTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json"), "missing fixture \(name)")
        return try Data(contentsOf: url)
    }
    private let ram = AlbumQuery(artist: "Daft Punk", album: "Random Access Memories")

    func testNormalizeAndSimilarity() {
        XCTAssertEqual(Matching.normalize("Beyoncé — LEMONADE!"), "beyonce lemonade")
        XCTAssertEqual(Matching.baseTitle("Random Access Memories (10th Anniversary Edition)"), "Random Access Memories")
        XCTAssertEqual(Matching.baseTitle("Abbey Road - Remastered 2019"), "Abbey Road")
        XCTAssertEqual(Matching.similarity("Daft Punk", "daft punk"), 1)
        XCTAssertLessThan(Matching.similarity("Daft Punk", "Justice"), 0.2)
    }

    func testClassification() {
        XCTAssertEqual(Matching.classify(types: ["Medium"]), .label)
        XCTAssertEqual(Matching.classify(types: ["Front", "Medium"]), .edition, "product photo, not a label")
        XCTAssertEqual(Matching.classify(types: ["Booklet", "Medium", "Tray"]), .edition)
        XCTAssertEqual(Matching.classify(types: ["Front"]), .edition)
        XCTAssertEqual(Matching.classify(types: ["Back"]), .skip)
        XCTAssertEqual(Matching.classify(types: []), .skip, "untyped images are never used")
    }

    func testSideDetection() {
        XCTAssertEqual(Matching.sideKind(from: "Side A label"), .sideA)
        XCTAssertEqual(Matching.sideKind(from: "disc 1, B-side"), .sideB)
        XCTAssertNil(Matching.sideKind(from: "Disc 1"))
    }

    func testHttpUpgradedHttpsOnly() {
        XCTAssertEqual(Matching.secure("http://coverartarchive.org/x.jpg")?.scheme, "https")
        XCTAssertNil(Matching.secure("ftp://x/y.jpg"))
    }

    func testPicksTheRightReleaseGroup() throws {
        let groups = try JSONDecoder().decode(MBReleaseGroupSearch.self, from: fixture("mb_releasegroup_ram")).releaseGroups
        let g = try XCTUnwrap(Matching.pickGroup(groups, query: ram))
        XCTAssertEqual(g.id, "aa997ea0-2936-40bd-884d-3af8a0e064dc")
        XCTAssertNil(Matching.pickGroup(groups, query: AlbumQuery(artist: "Daft Punk", album: "Homework")), "never guess")
        XCTAssertNil(Matching.pickGroup(groups, query: AlbumQuery(artist: "Someone Else", album: "Random Access Memories")))
    }

    func testCandidateReleasesAreVinylOnly() throws {
        let groups = try JSONDecoder().decode(MBReleaseGroupSearch.self, from: fixture("mb_releasegroup_ram")).releaseGroups
        let releases = try JSONDecoder().decode(MBReleaseList.self, from: fixture("mb_releases_ram")).releases
        XCTAssertGreaterThan(releases.count, 10)
        let c = Matching.candidateReleases(releases, group: groups[0], query: ram)
        XCTAssertEqual(Set(c.map { $0.0.id }), ["4375c18f-f160-44d0-ae2b-795f1dd5870f", "4867ceba-ffe7-40c0-a093-45be6c03c655",
                                                 "ecf72e5a-e378-485e-bb87-7ebbd0430a79", "fc1eb6d6-1c46-429a-8332-4f881c541ae7"])
        XCTAssertTrue(c.allSatisfy { $0.1 > 0.9 })
    }

    func testBarcodeAndYearMoveConfidence() {
        let base = Matching.confidence(query: ram, artist: "Daft Punk", title: "Random Access Memories", isVinyl: true, date: "2013", barcode: "888837168618")
        var q = ram; q.year = "2013"; q.barcode = "888837168618"
        let hit = Matching.confidence(query: q, artist: "Daft Punk", title: "Random Access Memories", isVinyl: true, date: "2013-05-17", barcode: "888837168618")
        let miss = Matching.confidence(query: q, artist: "Daft Punk", title: "Random Access Memories", isVinyl: true, date: "1999", barcode: "000000000001")
        XCTAssertGreaterThan(hit, miss)
        XCTAssertEqual(base, 1, accuracy: 0.001)
        let wrong = Matching.confidence(query: ram, artist: "Daft Punk", title: "Homework", isVinyl: true, date: nil, barcode: nil)
        XCTAssertLessThan(wrong, 0.8)
    }

    func testLabelScansAreTaggedButProductPhotosAreNot() throws {
        let groups = try JSONDecoder().decode(MBReleaseGroupSearch.self, from: fixture("mb_releasegroup_ram")).releaseGroups
        let releases = try JSONDecoder().decode(MBReleaseList.self, from: fixture("mb_releases_ram")).releases
        let lp = try XCTUnwrap(releases.first { $0.id == "4867ceba-ffe7-40c0-a093-45be6c03c655" })
        let box = try XCTUnwrap(releases.first { $0.id == "4375c18f-f160-44d0-ae2b-795f1dd5870f" })
        let lpIndex = try JSONDecoder().decode(CAAIndex.self, from: fixture("caa_ram_2013_lp"))
        let boxIndex = try JSONDecoder().decode(CAAIndex.self, from: fixture("caa_ram_2023_10th"))

        let a = Matching.variants(release: lp, group: groups[0], index: lpIndex, confidence: 1, query: ram)
        XCTAssertEqual(a.filter { $0.verification == .tagged }.count, 3, "three Medium-only scans")
        XCTAssertEqual(a.filter { $0.kind == .edition }.count, 1, "the Front cover")
        XCTAssertTrue(a.allSatisfy { $0.imageURL?.scheme == "https" })
        XCTAssertEqual(a.first?.format, "12\" Vinyl ×2")

        let b = Matching.variants(release: box, group: groups[0], index: boxIndex, confidence: 1, query: ram)
        XCTAssertEqual(b.count, 4)
        XCTAssertTrue(b.allSatisfy { $0.verification == .unverified }, "Medium + Front/Booklet must never be called a label")
        XCTAssertTrue(b.allSatisfy { $0.kind == .edition })
    }

    func testRankingPutsTaggedFirstAndDedupes() throws {
        let groups = try JSONDecoder().decode(MBReleaseGroupSearch.self, from: fixture("mb_releasegroup_ram")).releaseGroups
        let releases = try JSONDecoder().decode(MBReleaseList.self, from: fixture("mb_releases_ram")).releases
        let lp = try XCTUnwrap(releases.first { $0.id == "4867ceba-ffe7-40c0-a093-45be6c03c655" })
        let lpIndex = try JSONDecoder().decode(CAAIndex.self, from: fixture("caa_ram_2013_lp"))
        let v = Matching.variants(release: lp, group: groups[0], index: lpIndex, confidence: 1, query: ram)
        let ranked = Matching.rank(v + v)
        XCTAssertEqual(ranked.count, v.count)
        XCTAssertEqual(ranked.first?.verification, .tagged)
        XCTAssertEqual(ranked.last?.kind, .edition)
    }

    func testVariantCodableRoundTrip() throws {
        let v = ArtworkVariant(id: "caa:1", kind: .vinylLabel, verification: .tagged, source: .musicBrainz,
                               imageURL: URL(string: "https://example.org/a.jpg"), year: "2013", confidence: 0.9)
        let back = try JSONDecoder().decode(ArtworkVariant.self, from: JSONEncoder().encode(v))
        XCTAssertEqual(v, back)
    }

    func testAlbumKeySeparatesEditions() {
        XCTAssertNotEqual(AlbumQuery(artist: "A", album: "X").key, AlbumQuery(artist: "A", album: "X (Deluxe)").key)
        XCTAssertEqual(AlbumQuery(artist: "Daft Punk", album: "RAM").key, AlbumQuery(artist: "daft punk", album: "ram!").key)
    }
}

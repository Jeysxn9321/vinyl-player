import XCTest
@testable import Vinyl

final class LyricsAndSidesTests: XCTestCase {
    func testParseBasic() {
        let l = LyricsLoader.parseLRC("[00:12.50]Hello\n[01:02.00]World")
        XCTAssertEqual(l.map(\.text), ["Hello", "World"])
        XCTAssertEqual(l[0].time ?? 0, 12.5, accuracy: 0.001)
        XCTAssertEqual(l[1].time ?? 0, 62, accuracy: 0.001)
    }
    func testParseCRLFAndTags() {
        let l = LyricsLoader.parseLRC("[ar:Someone]\r\n[00:01.00]One\r\n[00:02.00]Two\r\n")
        XCTAssertEqual(l.map(\.text), ["One", "Two"])
    }
    func testParseMultiTimestampSorted() {
        let l = LyricsLoader.parseLRC("[00:30.00]B\n[00:10.00][00:50.00]A")
        XCTAssertEqual(l.map(\.text), ["A", "B", "A"])
        XCTAssertEqual(l.map(\.id), [0, 1, 2])
    }
    func testSidesSplit() {
        let even = AlbumSides.split(Array(1...8)); XCTAssertEqual(even.a.count, 4); XCTAssertEqual(even.b.count, 4)
        let odd = AlbumSides.split(Array(1...9)); XCTAssertEqual(odd.a.count, 5); XCTAssertEqual(odd.b, [6, 7, 8, 9])
    }
    func testTrackActionsIDs() {
        XCTAssertEqual(TrackActions.spotifyURI("4uLU6hMCjMI75M1A2tKUQC"), "spotify:track:4uLU6hMCjMI75M1A2tKUQC")
        XCTAssertNil(TrackActions.spotifyURI("Title|Artist"))
        XCTAssertTrue(TrackActions.isStoreID("1440857781")); XCTAssertFalse(TrackActions.isStoreID("abc"))
    }
}

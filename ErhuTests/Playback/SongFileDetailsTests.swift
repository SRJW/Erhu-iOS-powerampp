import XCTest
@testable import Erhu

final class SongFileDetailsTests: XCTestCase {
    func testSharedM4AContainerDoesNotHideTheRealCodec() {
        var song = Song(id: 1, title: "Track", artist: "Artist", album: "Album", durationMs: 61_000, path: "track.m4a")
        song.codec = "ALAC"
        XCTAssertEqual(SongRowText.fileDetails(song), "1:01 | ALAC · m4a")
        song.codec = "AAC"
        XCTAssertEqual(SongRowText.fileDetails(song), "1:01 | AAC · m4a")
        song.codec = "HE-AAC v2"
        XCTAssertEqual(SongRowText.fileDetails(song), "1:01 | HE-AAC V2 · m4a")
        song.codec = nil
        XCTAssertEqual(SongRowText.fileDetails(song), "1:01 | m4a", "Unknown codecs must not be guessed from an extension")
    }
}

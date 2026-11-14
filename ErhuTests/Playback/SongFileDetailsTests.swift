import XCTest
import AVFoundation
@testable import Erhu

final class SongFileDetailsTests: XCTestCase {
    func testScannerDistinguishesActualAACAndALACAndRepairsAmbiguousCachedCodecs() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100))
        buffer.frameLength = 44_100
        for frame in 0..<Int(buffer.frameLength) { buffer.floatChannelData?[0][frame] = 0 }
        for (name, codec) in [("aac", kAudioFormatMPEG4AAC), ("alac", kAudioFormatAppleLossless)] {
            let url = folder.appendingPathComponent(name + ".m4a")
            do {
                let file = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey: codec, AVSampleRateKey: 44_100,
                                                                     AVNumberOfChannelsKey: 1, AVEncoderBitDepthHintKey: 16])
                try file.write(from: buffer)
            }
            XCTAssertEqual(AudioFormatInfo.read(url, fileSize: 0).codec, name.uppercased())
        }
        let database = try LibraryDatabase.inMemory()
        let scanner = LibraryScanner(database: database, folder: folder)
        _ = try scanner.scan()
        try database.db.execute("UPDATE songs SET codec = 'AAC/ALAC', is_favorite = 1")
        _ = try scanner.scan()
        let songs = try database.allSongs()
        XCTAssertEqual(Set(songs.compactMap(\.codec)), Set(["AAC", "ALAC"]))
        XCTAssertTrue(songs.allSatisfy(\.isFavorite), "Repair must preserve listener metadata")
    }

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

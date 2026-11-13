import XCTest
@testable import Erhu

final class PlayerButtonActionTests: XCTestCase {
    @MainActor private func fixture(album: String = "Album") throws -> (LibraryStore, Song, URL) {
        let database = try LibraryDatabase.inMemory()
        let folder = LibraryPaths.musicFolder.appendingPathComponent("player-actions-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let path = folder.lastPathComponent + "/Track.m4a"
        try Data([0, 1, 2]).write(to: folder.appendingPathComponent("Track.m4a"))
        try database.db.execute("""
            INSERT INTO songs (id, title, artist, album, artist_id, album_id, duration_ms, uri, file_path, track_number, year, date_modified)
            VALUES (1, 'Track', 'Artist', ?, 1, 7, 180000, ?, ?, 1, 2020, 0)
            """, [album, path, path])
        try database.db.execute("INSERT INTO albums (id, title, artist, artist_id, song_count, year) VALUES (7, ?, 'Artist', 1, 1, 2020)", [album])
        let library = LibraryStore(database: database)
        return (library, try XCTUnwrap(library.songs.first), folder)
    }

    @MainActor func testTitleRevealsPlaylistAndAlbumLineRevealsAlbum() throws {
        let (library, song, folder) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let playlist = try library.database.createPlaylist(name: "Test", songIds: [song.id])
        library.reload()
        let router = AppRouter()
        router.showsNowPlaying = true
        XCTAssertTrue(router.revealSong(song, album: false, source: .playlist(playlist), library: library))
        XCTAssertEqual(router.section, .library)
        XCTAssertEqual(router.songReveal?.destination, .playlist(playlist))
        XCTAssertEqual(router.songReveal?.songID, song.id)
        XCTAssertFalse(router.showsNowPlaying)
        XCTAssertTrue(router.revealSong(song, album: true, source: .playlist(playlist), library: library))
        XCTAssertEqual(router.songReveal?.destination, .album(song.albumId))
    }

    @MainActor func testUnknownAlbumAndMissingPlaylistFallBackToContainingFolder() throws {
        let (library, song, folder) = try fixture(album: unknownAlbum)
        defer { try? FileManager.default.removeItem(at: folder) }
        let router = AppRouter()
        XCTAssertTrue(router.revealSong(song, album: true, source: .library, library: library))
        XCTAssertEqual(router.songReveal?.destination, .songFolder(folder.lastPathComponent))
        XCTAssertTrue(router.revealSong(song, album: false, source: .playlist(9999), library: library))
        XCTAssertEqual(router.songReveal?.destination, .songFolder(folder.lastPathComponent))
    }

    @MainActor func testDeletedFileReturnsToLibraryRootWithoutStaleHighlight() throws {
        let (library, song, folder) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let router = AppRouter()
        XCTAssertTrue(router.revealSong(song, album: true, source: .library, library: library))
        router.highlightedSongID = song.id
        try FileManager.default.removeItem(at: song.url)
        XCTAssertFalse(router.revealSong(song, album: false, source: .library, library: library))
        XCTAssertEqual(router.section, .library)
        XCTAssertEqual(router.paths[.library]?.count, 0)
        XCTAssertNil(router.songReveal)
        XCTAssertNil(router.highlightedSongID)
    }
}

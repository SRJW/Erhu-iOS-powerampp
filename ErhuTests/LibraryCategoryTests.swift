import XCTest
@testable import Erhu

final class LibraryCategoryTests: XCTestCase {
    func testHidingDoesNotLoseSavedOrderAndHiddenSectionsCanBeRestored() {
        let order = "albums,songs,playlists"
        let hidden = "albums,radio,albums,retired"
        XCTAssertEqual(LibraryCategory.hidden(hidden), [.albums, .radio])
        let visible = LibraryCategory.visible(order: order, hidden: hidden)
        XCTAssertEqual(Array(visible.prefix(2)), [.songs, .playlists])
        XCTAssertFalse(visible.contains(.albums))
        XCTAssertFalse(visible.contains(.radio))
        XCTAssertEqual(LibraryCategory.visible(order: order, hidden: "").first, .albums)
        let allHidden = LibraryCategory.allCases.map(\.rawValue).joined(separator: ",")
        XCTAssertTrue(LibraryCategory.visible(order: order, hidden: allHidden).isEmpty)
    }

    func testOldCategoryOrderRetainsEveryCategoryExactlyOnce() {
        let migrated = LibraryCategory.ordered("playlists,favorites,artists,songs,vybe,songs")
        XCTAssertEqual(Array(migrated.prefix(4)), [.playlists, .favorites, .artists, .songs])
        XCTAssertEqual(Set(migrated), Set(LibraryCategory.allCases))
        XCTAssertEqual(migrated.count, LibraryCategory.allCases.count)
    }

    func testAlphabetHandlesAccentsNumbersAndCurrentFilteredOrder() {
        let songs = [Song(id: 1, title: "Álbum", artist: "A", album: "B", durationMs: 1, path: "1.m4a"),
                     Song(id: 2, title: "Árbol", artist: "A", album: "B", durationMs: 1, path: "2.m4a"),
                     Song(id: 3, title: "3005", artist: "A", album: "B", durationMs: 1, path: "3.m4a")]
        XCTAssertEqual(SongAlphabet.anchors(songs), ["A": 1, "#": 3])
        XCTAssertEqual(SongAlphabet.anchors(Array(songs.reversed())), ["A": 2, "#": 3])
        XCTAssertEqual(SongAlphabet.anchors([songs[1]]), ["A": 2])
    }

    func testAdditionalSearchTypesRespectFolderPathsAndAlbumArtists() {
        let song = Song(id: 1, title: "Track", artist: "Guest", album: "Record", durationMs: 1, path: "Colección/track.m4a")
        let artist = Artist(id: 9, name: "Álvaro", songCount: 1, albumCount: 1)
        let playlist = Playlist(id: 2, name: "Colección", songCount: 1)
        let folders = LibrarySearchExtras.matching("coleccion", songs: [song], albumArtists: [artist], playlists: [playlist])
        XCTAssertEqual(folders.folders, ["Colección"])
        XCTAssertEqual(folders.playlists.map(\.id), [2])
        XCTAssertTrue(folders.albumArtists.isEmpty)
        let artists = LibrarySearchExtras.matching("alvaro", songs: [song], albumArtists: [artist], playlists: [playlist])
        XCTAssertEqual(artists.albumArtists.map(\.id), [9])
    }

    func testAlbumArtistsComeFromTheirRelationshipNotTheTrackCredit() throws {
        let database = try LibraryDatabase.inMemory()
        try database.db.execute("INSERT INTO album_artist_cross_ref (album_id, artist_id, position) VALUES (10, 9, 0), (11, 9, 0), (12, 8, 0)")
        XCTAssertEqual(try database.albumArtistAlbumIDs(), [9: Set([10, 11]), 8: Set([12])])
    }
}

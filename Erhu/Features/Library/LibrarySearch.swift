import Foundation

enum SearchType: String, CaseIterable, Identifiable {
    case all = "All", songs = "Songs", albums = "Albums", artists = "Artists", albumArtists = "Album Artists", folders = "Folders", playlists = "Playlists"
    var id: String { rawValue }
}

struct LibrarySearchExtras: Sendable {
    var albumArtists: [Artist] = []
    var folders: [String] = []
    var playlists: [Playlist] = []
    static func matching(_ query: String, songs: [Song], albumArtists: [Artist], playlists: [Playlist]) -> Self {
        guard !query.trimmed.isEmpty else { return Self() }
        return Self(albumArtists: albumArtists.filter { SearchNormalizer.matches($0.name, query) },
                    folders: Set(songs.map { ($0.path as NSString).deletingLastPathComponent })
                        .filter { SearchNormalizer.matches($0, query) }.sorted(),
                    playlists: playlists.filter { SearchNormalizer.matches($0.name, query) })
    }
}

/// Results belong to the entity named by the query; related rows come from library relationships.
struct LibrarySearchResults: Sendable {
    var artists: [Artist] = []
    var albums: [Album] = []
    var songs: [Song] = []
}

enum LibrarySearch {
    static func results(_ query: String, songs: [Song], albums: [Album], artists: [Artist]) -> LibrarySearchResults {
        guard !SearchNormalizer.normalize(query).isEmpty else { return LibrarySearchResults() }
        let tokens = SearchNormalizer.normalizeWords(query).split(separator: " ").map(String.init)
        func qualifiedScore(_ name: String, _ artist: String) -> Int {
            guard tokens.count >= 2, tokens.indices.contains(where: { index in
                SearchNormalizer.matches(name, tokens[index]) && tokens.indices.contains {
                    $0 != index && SearchNormalizer.matches(artist, tokens[$0])
                }
            }) else { return 0 }
            return SearchNormalizer.score(name + " " + artist, query)
        }
        func scoreAlbum(_ album: Album) -> Int {
            let name = SearchNormalizer.score(album.title, query)
            let base = album.title.replacingOccurrences(of: #"\s*[(\[][^)\]]*(?:deluxe|expanded|anniversary|edition)[^)\]]*[)\]]"#, with: "", options: [.regularExpression, .caseInsensitive])
            let edition = base != album.title && SearchNormalizer.score(base, query) == 100 ? 98 : 0
            let qualified = qualifiedScore(album.title, album.artist)
            return max(name, edition, qualified == 100 ? 97 : qualified == 75 ? 85 : qualified == 60 ? 55 : 0)
        }
        var rankedArtists: [(Artist, Int)] = artists.map { artist in
            (artist, SearchNormalizer.score(artist.name, query))
        }
        rankedArtists.removeAll { $0.1 <= 0 }
        rankedArtists.sort { a, b in
            if a.1 != b.1 { return a.1 > b.1 }
            return a.0.id < b.0.id
        }
        var rankedAlbums: [(Album, Int)] = albums.map { album in (album, scoreAlbum(album)) }
        rankedAlbums.removeAll { $0.1 <= 0 }
        rankedAlbums.sort { a, b in
            if a.1 != b.1 { return a.1 > b.1 }
            return a.0.id < b.0.id
        }
        var rankedSongs: [(Song, Int)] = songs.map { song in
            let direct = SearchNormalizer.score(song.title, query)
            let qualified = qualifiedScore(song.title, song.artist)
            let qualifiedRank: Int
            switch qualified {
            case 100: qualifiedRank = 98
            case 75: qualifiedRank = 88
            case 60: qualifiedRank = 55
            default: qualifiedRank = 0
            }
            return (song, max(direct, qualifiedRank))
        }
        rankedSongs.removeAll { $0.1 <= 0 }
        rankedSongs.sort { a, b in
            if a.1 != b.1 { return a.1 > b.1 }
            return a.0.id < b.0.id
        }
        let artistScore = rankedArtists.first?.1 ?? 0, albumScore = rankedAlbums.first?.1 ?? 0, songScore = rankedSongs.first?.1 ?? 0
        guard max(artistScore, albumScore, songScore) > 0 else { return LibrarySearchResults() }
        func ordered(_ songs: [Song]) -> [Song] {
            songs.sorted {
                if $0.albumId != $1.albumId { return $0.albumId < $1.albumId }
                if $0.discNumber != $1.discNumber { return $0.discNumber < $1.discNumber }
                if $0.trackNumber != $1.trackNumber { return $0.trackNumber < $1.trackNumber }
                return $0.id < $1.id
            }
        }
        // Exact artist names, then exact album names (including a marked deluxe edition).
        // A song-title match otherwise supplies its albums without expanding to their other songs.
        if artistScore == 100 || (albumScore < 98 && artistScore >= max(albumScore, songScore)) {
            let found = rankedArtists.filter { $0.1 == artistScore }.map { $0.0 }
            let ids = Set(found.map(\.id)), names = Set(found.map { SearchNormalizer.normalize($0.name) })
            let related = songs.filter { song in
                ids.contains(song.artistId) || MusicQueryIntent.artists(song.artist).contains { names.contains(SearchNormalizer.normalize($0)) }
            }
            let albumIDs = Set(related.map(\.albumId))
            return LibrarySearchResults(artists: found, albums: albums.filter { albumIDs.contains($0.id) }, songs: ordered(related))
        }
        if albumScore >= 98 || albumScore >= songScore {
            let found = rankedAlbums.filter { $0.1 == albumScore }.map { $0.0 }
            let ids = Set(found.map(\.id))
            return LibrarySearchResults(albums: found, songs: ordered(songs.filter { ids.contains($0.albumId) }))
        }
        let found = rankedSongs.filter { $0.1 == songScore }.map { $0.0 }
        let ids = Set(found.map(\.albumId))
        return LibrarySearchResults(albums: albums.filter { ids.contains($0.id) }, songs: found)
    }
}

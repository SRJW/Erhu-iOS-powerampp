import SwiftUI
import Observation

/// The primary destinations of the shared four-button navigation bar.
enum LibrarySection: String, CaseIterable, Identifiable {
    case library, equalizer, search
    var id: String { rawValue }

    var label: String {
        switch self {
        case .library: "Library"
        case .equalizer: "Equalizer"
        case .search: "Search"
        }
    }

    var icon: String {
        switch self {
        case .library: "music.note.house"
        case .equalizer: "slider.vertical.3"
        case .search: "magnifyingglass"
        }
    }

    var selectedIcon: String {
        switch self {
        case .library: "music.note.house.fill"
        case .equalizer: "slider.vertical.3"
        case .search: "magnifyingglass"
        }
    }
}

/// The full shelves the Library overview opens with "More".
enum LibraryShelf: String, Hashable {
    case playlists, favorites, artists

    var label: String {
        switch self {
        case .playlists: "Playlists"
        case .favorites: "Favorites"
        case .artists: "Artists"
        }
    }
}

/// Tools opened from the anchored bottom menu.
enum Tool: String, CaseIterable, Identifiable, Hashable {
    case soundCapsule, equalizer, autoFixTags, libraryBuilder, artworkFetcher, wifiTransfer, settings
    var id: String { rawValue }

    var label: String {
        switch self {
        case .soundCapsule: "Sound Capsule"
        case .equalizer: "Equalizer"
        case .autoFixTags: "Auto Fix Tags"
        case .libraryBuilder: "Library Builder"
        case .artworkFetcher: "Artwork Fetcher"
        case .wifiTransfer: "Wi-Fi Transfer"
        case .settings: "Settings"
        }
    }

    var icon: String {
        switch self {
        case .soundCapsule: "chart.bar.xaxis"
        case .equalizer: "slider.vertical.3"
        case .autoFixTags: "wand.and.stars"
        case .libraryBuilder: "folder"
        case .artworkFetcher: "photo.on.rectangle.angled"
        case .wifiTransfer: "wifi"
        case .settings: "gearshape"
        }
    }
}

/// A page pushed inside a section.
enum Route: Hashable {
    case album(Int64)
    case artist(Int64)
    case playlist(Int64)
    case radio(RadioSeed)
    case shelf(LibraryShelf)
    case allSongs
    case category(LibraryCategory)
    case songFolder(String)
    case tool(Tool)
    case settingsPage(SettingsPageRoute)
    case transitionStudio(CollectionRef)
}

/// Where the app is: the section, each section's own back stack, and what is presented on top.
@MainActor
@Observable
final class AppRouter {
    var section: LibrarySection = .library
    var paths: [LibrarySection: NavigationPath] = Dictionary(uniqueKeysWithValues: LibrarySection.allCases.map { ($0, NavigationPath()) })
    var scrollToTopRequests: [LibrarySection: Int] = [:]
    var showsSearch: Bool {
        get { section == .search }
        set { if newValue { activate(.search) } }
    }
    var showsImporter = false
    var showsDrawer = false
    var showsNowPlaying = false
    var presentedTool: Tool?
    var toolPath = NavigationPath()
    var songsForPlaylist: [Song]?
    var songForDetails: Song?
    /// The song whose tags are being edited by hand.
    var songForTagEdit: Song?
    var songReveal: SongRevealRequest?
    var highlightedSongID: Int64?
    var showsNewPlaylist = false

    func open(_ route: Route) {
        if presentedTool != nil { toolPath.append(route) }
        else { paths[section, default: NavigationPath()].append(route) }
    }

    func open(_ tool: Tool) {
        showsDrawer = false
        if tool == .equalizer { activate(.equalizer) }
        else { toolPath = NavigationPath(); presentedTool = tool }
    }

    func activate(_ target: LibrarySection) {
        presentedTool = nil
        showsNowPlaying = false
        showsDrawer = false
        if target == .library { select(target) }
        else { section = target }
    }

    func openPlayer() {
        presentedTool = nil
        showsDrawer = false
        showsNowPlaying = true
    }

    /// A tab always opens its root. Reselecting it also scrolls that root back to the top.
    func select(_ target: LibrarySection) {
        presentedTool = nil
        let reselecting = target == section
        paths[target] = NavigationPath()
        section = target
        showsDrawer = false
        if reselecting { scrollToTopRequests[target, default: 0] += 1 }
    }

    func binding(for section: LibrarySection) -> Binding<NavigationPath> {
        Binding(get: { self.paths[section] ?? NavigationPath() }, set: { self.paths[section] = $0 })
    }

    func reveal(_ source: PlaybackSource) {
        let destination: Route?
        switch source {
        case .album(let id): section = .library; destination = .album(id)
        case .playlist(let id): section = .library; destination = .playlist(id)
        case .artist(let id): section = .library; destination = .artist(id)
        case .smartPlaylist(let title):
            section = .library
            let category: LibraryCategory = title == SmartPlaylist.mostPlayed.rawValue ? .mostPlayed : title == SmartPlaylist.recentlyAdded.rawValue ? .recentlyAdded : .recentlyPlayed
            destination = .category(category)
        case .library: section = .library; destination = .allSongs
        case .favorites: section = .library; destination = .shelf(.favorites)
        case .vybe: section = .library; destination = .allSongs
        }
        paths[section] = destination.map { NavigationPath([$0]) } ?? NavigationPath()
        showsDrawer = false
        showsSearch = false
        showsNowPlaying = false
    }

    /// Resolve the current database entry before navigating; never alter playback.
    @discardableResult
    func revealSong(_ song: Song, album: Bool, source: PlaybackSource?, library: LibraryStore) -> Bool {
        showsNowPlaying = false
        showsSearch = false
        songReveal = nil
        highlightedSongID = nil
        select(.library)
        guard let current = library.songs.first(where: { $0.id == song.id }),
              PreparedAudioShare.available(current.url) else { return false }
        let destination: Route
        if album, !current.album.trimmed.isEmpty, current.album != unknownAlbum,
           library.album(current.albumId) != nil {
            destination = .album(current.albumId)
        } else if !album, case .playlist(let id) = source,
                  library.playlist(id) != nil,
                  (try? library.database.playlistEntries(id).contains(where: { $0.song.id == current.id })) == true {
            destination = .playlist(id)
        } else {
            destination = .songFolder((current.path as NSString).deletingLastPathComponent)
        }
        songReveal = SongRevealRequest(songID: current.id, destination: destination)
        open(destination)
        return true
    }

    func songActions(_ actions: LibraryActions, source: PlaybackSource? = nil) -> SongActions {
        SongActions(
            toggleFavorite: { actions.toggleFavorite($0) },
            playNext: { actions.playNext($0, source: source) },
            addToQueue: { actions.addToQueue($0, source: source) },
            startRadio: { [weak self] song in
                guard let self else { return }
                self.open(.radio(.song(song.id)))
            },
            addToPlaylist: { [weak self] song in self?.songsForPlaylist = [song] },
            viewDetails: { [weak self] song in self?.songForDetails = song },
            editTags: { [weak self] song in self?.songForTagEdit = song },
            fixTags: { song in actions.fixTags([song]) },
            deleteFromDevice: { actions.songPendingDeletion = $0 }
        )
    }
}

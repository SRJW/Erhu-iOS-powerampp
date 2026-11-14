import SwiftUI

/// Existing album/artist/playlist cards live inside one category scaffold.
struct EntityCategoryView: View {
    let category: LibraryCategory
    @Environment(LibraryStore.self) private var library
    @Environment(LibraryActions.self) private var actions
    @Environment(AppRouter.self) private var router
    @AppStorage private var sort: String
    @State private var query = ""
    @State private var showsSearch = false
    @State private var selecting = false
    @State private var selected = Set<Int64>()
    @FocusState private var focused: Bool
    private let columns = [GridItem(.adaptive(minimum: ArtworkSize.gridMin), spacing: Spacing.lg, alignment: .top)]

    init(category: LibraryCategory) {
        self.category = category
        _sort = AppStorage(wrappedValue: LibrarySort.title.rawValue, "library.\(category.rawValue).sort")
    }
    private var match: SectionSearch { SectionSearch(query) }
    private var albums: [Album] {
        AlbumBrowseRequest(albums: library.albums, songs: library.songs, facts: library.browseFacts,
                           lastPlayed: library.albumLastPlayed, query: query, sort: LibrarySort(rawValue: sort) ?? .title).results()
    }
    private var artists: [Artist] {
        let candidates = category == .albumArtists ? library.albumArtists : library.artists
        let sorted = candidates.filter { match.matches([$0.name]) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return sort == LibrarySort.titleDescending.rawValue ? sorted.reversed() : sorted
    }
    private var playlists: [Playlist] {
        let sorted = library.playlists.filter { match.matches([$0.name]) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return sort == LibrarySort.titleDescending.rawValue ? sorted.reversed() : sorted
    }
    private var folders: [String] {
        let sorted = Set(library.songs.map { ($0.path as NSString).deletingLastPathComponent }).filter { match.matches([$0]) }.sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
        return sort == LibrarySort.titleDescending.rawValue ? sorted.reversed() : sorted
    }
    private var songs: [Song] {
        switch category {
        case .albums:
            let ids = Set(albums.map(\.id)); return library.songs.filter { ids.contains($0.albumId) }
        case .artists:
            let ids = Set(artists.map(\.id)); return library.songs.filter { ids.contains($0.artistId) }
        case .albumArtists:
            let ids = artists.reduce(into: Set<Int64>()) { $0.formUnion(library.albumArtistAlbums[$1.id] ?? []) }
            return library.songs.filter { ids.contains($0.albumId) }
        case .folders:
            let paths = Set(folders); return library.songs.filter { paths.contains(($0.path as NSString).deletingLastPathComponent) }
        case .playlists:
            let ids = Set(playlists.flatMap { (try? library.database.playlistEntries($0.id))?.map(\.song.id) ?? [] })
            return library.songs.filter { ids.contains($0.id) }
        default: return library.songs.filter { match.matches([$0.title, $0.artist, $0.album]) }
        }
    }

    var body: some View {
        let tracks = songs
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                CategoryHeader(title: category.title, icon: category.icon, count: tracks.count, selecting: selecting,
                               shuffle: { remember(); actions.playShuffled(tracks) }, play: { remember(); actions.playInOrder(tracks) },
                               search: { showsSearch = true; focused = true },
                               select: { selecting.toggle(); if !selecting { selected.removeAll() } }) {
                    Picker("Sort by", selection: $sort) {
                        ForEach(category == .albums ? LibrarySort.albums : [.title, .titleDescending], id: \.rawValue) { Text($0.label).tag($0.rawValue) }
                    }
                    if category == .playlists { Button("New playlist", systemImage: "plus") { router.showsNewPlaylist = true } }
                    Button("Import music", systemImage: "plus") { router.showsImporter = true }
                }
                if showsSearch {
                    GlassSearchField(text: $query, prompt: "Search \(category.title.lowercased())", focused: $focused,
                                     close: { focused = false; showsSearch = false; query = "" },
                                     historyScope: "browse." + category.title.lowercased())
                        .padding(.horizontal, Spacing.gutter)
                    if query.trimmed.isEmpty {
                        RecentSearchesView(scope: "browse." + category.title.lowercased()) { query = $0; focused = true }
                            .padding(.horizontal, Spacing.gutter)
                    }
                }
                if selecting {
                    SongSelectionBar(songs: tracks, selected: $selected)
                    SongList(songs: tracks, emptyMessage: "No songs in this category.", emptyIcon: category.icon,
                             selection: $selected, showsFileDetails: true)
                } else { entities }
            }.padding(.vertical, Spacing.sm)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
        .refreshable { library.scan() }
    }

    @ViewBuilder private var entities: some View {
        switch category {
        case .albums:
            if query.trimmed.isEmpty, !library.featuredAlbums.isEmpty {
                Shelf(title: "Featured Albums") {
                    ForEach(library.featuredAlbums) { album in AlbumTile(album: album) { router.open(.album(album.id)) }.frame(width: ArtworkSize.shelf) }
                }
            }
            if albums.isEmpty { empty }
            grid { ForEach(albums) { album in AlbumTile(album: album) { remember(); router.open(.album(album.id)) } } }
        case .artists, .albumArtists:
            if artists.isEmpty { empty }
            grid { ForEach(artists) { artist in ArtistTile(artist: artist) { remember(); router.open(.artist(artist.id)) } } }
        case .playlists:
            if playlists.isEmpty { empty }
            grid { ForEach(playlists) { playlist in PlaylistTile(playlist: playlist) { remember(); router.open(.playlist(playlist.id)) } } }
        case .folders:
            if folders.isEmpty { empty }
            ForEach(folders, id: \.self) { folder in
                Button { remember(); router.open(.songFolder(folder)) } label: {
                    Label(folder.isEmpty ? "Music folder" : folder, systemImage: "folder")
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading).padding(.horizontal, Spacing.gutter)
                }.buttonStyle(.plain)
            }
        case .radio:
            if library.songs.isEmpty { empty } else { RadioStationShelf() }
        default: EmptyView()
        }
    }
    private var empty: some View { EmptyState(message: "No \(category.title.lowercased()) found.", systemImage: category.icon) }
    private func grid<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        LazyVGrid(columns: columns, spacing: Spacing.xl, content: content).padding(.horizontal, Spacing.gutter)
    }
    private func remember() { SearchHistoryStore.shared.remember(query, in: "browse." + category.title.lowercased()) }
}

struct SongSelectionBar: View {
    let songs: [Song]
    @Binding var selected: Set<Int64>
    @Environment(AppRouter.self) private var router
    @Environment(LibraryActions.self) private var actions
    @State private var pendingDeletion: [Song] = []
    @State private var confirmsDeletion = false
    private var selectedSongs: [Song] { songs.filter { selected.contains($0.id) } }
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("\(selectedSongs.count) selected").font(.headline)
            HStack {
                Button("Select all") { selected = Set(songs.map(\.id)) }
                Button("Clear") { selected.removeAll() }
            }
            HStack {
                Button("Add to playlist", systemImage: "text.badge.plus") { router.songsForPlaylist = selectedSongs }
                Button("Delete", systemImage: "trash", role: .destructive) { pendingDeletion = selectedSongs; confirmsDeletion = true }
            }.disabled(selectedSongs.isEmpty)
        }
        .buttonStyle(.bordered).padding(.horizontal, Spacing.gutter)
        .onChange(of: songs) { _, songs in selected.formIntersection(songs.map(\.id)) }
        .alert("Delete \(countLabel(pendingDeletion.count, "song")) from device?", isPresented: $confirmsDeletion) {
            Button("Delete from device", role: .destructive) { selected.subtract(actions.deleteFromDevice(pendingDeletion)); pendingDeletion = [] }
            Button("Cancel", role: .cancel) { pendingDeletion = [] }
        } message: { Text("This permanently removes the selected audio files from amp, Files, the library and playlists. It cannot be undone. Separate copies elsewhere are kept.") }
    }
}

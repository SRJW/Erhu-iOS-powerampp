import SwiftUI

/// Songs keeps amp's theme, with collection-wide play, focused tools and explicit bulk actions.
struct AllSongsView: View {
    var folderPath: String? = nil
    var category: LibraryCategory = .songs
    @Environment(LibraryStore.self) private var library
    @Environment(LibraryActions.self) private var actions
    @Environment(AppRouter.self) private var router
    @AppStorage private var sort: String
    @State private var selecting = false
    @State private var selected = Set<Int64>()
    @State private var pendingDeletion: [Song] = []
    @State private var confirmsDeletion = false
    @State private var query = ""
    @State private var showsSearch = false
    @State private var showsFilters = false
    @State private var added = SongAddedPeriod.any
    @State private var genre = ""
    @State private var mood = LibraryMood.all
    @State private var results: [Song]?
    @State private var genres: [String] = []
    @FocusState private var searchFocused: Bool

    init(folderPath: String? = nil, category: LibraryCategory = .songs) {
        self.folderPath = folderPath
        self.category = category
        let key = category == .songs ? "library.songs.sort" : "library.\(category.rawValue).sort"
        _sort = AppStorage(wrappedValue: category.defaultSort.rawValue, key)
    }

    private var scopedSongs: [Song] {
        guard let folderPath else {
            switch category {
            case .favorites: return library.favorites
            case .mostPlayed: return library.songs.filter { (library.browseFacts[$0.id]?.plays ?? 0) > 0 }
            case .recentlyPlayed: return library.songs.filter { (library.browseFacts[$0.id]?.lastPlayedAt ?? 0) > 0 }
            default: return library.songs
            }
        }
        return library.songs.filter { ($0.path as NSString).deletingLastPathComponent == folderPath }
    }
    private var title: String {
        guard let folderPath else { return category.title }
        let name = (folderPath as NSString).lastPathComponent
        return name.isEmpty ? "Music folder" : name
    }
    private var hasFilters: Bool { added != .any || !genre.isEmpty || mood != .all }
    private var request: SongBrowseRequest {
        let now = LibraryDatabase.now()
        let facts = library.browseFacts
        let songs = added == .any ? scopedSongs : scopedSongs.filter { added.contains(facts[$0.id]?.addedAt ?? $0.dateModified, now: now) }
        return SongBrowseRequest(songs: songs, facts: facts, query: query,
                                 sort: LibrarySort(rawValue: sort) ?? .title, genre: genre, mood: mood)
    }
    private var selectedSongs: [Song] {
        SongBrowseRequest(songs: scopedSongs.filter { selected.contains($0.id) }, facts: library.browseFacts,
                          query: "", sort: LibrarySort(rawValue: sort) ?? .title).results()
    }

    var body: some View {
        PlayerSongReveal(destination: folderPath.map(Route.songFolder) ?? (category == .songs ? .allSongs : .category(category)),
                         songs: results ?? [], alphabetEnabled: sort == LibrarySort.title.rawValue || sort == LibrarySort.titleDescending.rawValue) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    header
                    if showsFilters { filters }
                    if showsSearch {
                        VStack(spacing: Spacing.sm) {
                            GlassSearchField(text: $query, prompt: "Search songs", focused: $searchFocused,
                                             close: closeSearch, identifier: "sectionSearchField", historyScope: "songs")
                            if query.trimmed.isEmpty {
                                RecentSearchesView(scope: "songs") { query = $0; searchFocused = true }
                            }
                        }
                        .padding(.horizontal, Spacing.gutter)
                        .task { searchFocused = true }
                    }
                    if selecting { selectionActions }
                    if category == .recentlyPlayed { recentCollections }
                    if let results {
                        if hasFilters || !query.trimmed.isEmpty {
                            Text("\(results.count) \(results.count == 1 ? "match" : "matches")").font(.caption).foregroundStyle(.secondary)
                                .padding(.horizontal, Spacing.gutter)
                        }
                        SongList(songs: results, emptyMessage: scopedSongs.isEmpty ? "No songs found." : "No songs match these filters.",
                                 emptyIcon: "music.note", source: playbackSource, selection: selecting ? $selected : nil, showsFileDetails: true,
                                 onPlay: { SearchHistoryStore.shared.remember(query, in: "songs") })
                    } else { ProgressView().frame(maxWidth: .infinity).padding() }
                }.padding(.top, Spacing.sm)
            }
            .accessibilityIdentifier("songsPage")
        }
        .tracksLibraryScrolling()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: request) {
            let snapshot = request
            if !snapshot.query.isEmpty { try? await Task.sleep(for: .milliseconds(120)) }
            guard !Task.isCancelled else { return }
            let updated = await Task.detached(priority: .userInitiated) {
                (snapshot.results(), LibraryBrowse.genres(in: snapshot.songs))
            }.value
            guard !Task.isCancelled else { return }
            results = updated.0; genres = updated.1
        }
        .refreshable { library.scan() }
        .onChange(of: library.songs) { _, songs in selected.formIntersection(Set(songs.map(\.id))) }
        .alert("Delete \(countLabel(pendingDeletion.count, "song")) from device?", isPresented: $confirmsDeletion) {
            Button("Delete from device", role: .destructive) {
                let deleted = actions.deleteFromDevice(pendingDeletion)
                selected.subtract(deleted)
                pendingDeletion = []
                if selected.isEmpty { selecting = false }
            }
            Button("Cancel", role: .cancel) { pendingDeletion = [] }
        } message: {
            Text("This permanently removes the selected audio files from amp, Files, the library and playlists. It cannot be undone. Separate copies elsewhere are kept.")
        }
    }

    private var playbackSource: PlaybackSource {
        switch category {
        case .favorites: .favorites
        case .mostPlayed: .smartPlaylist(SmartPlaylist.mostPlayed.rawValue)
        case .recentlyPlayed: .smartPlaylist(SmartPlaylist.recentlyPlayed.rawValue)
        case .recentlyAdded: .smartPlaylist(SmartPlaylist.recentlyAdded.rawValue)
        default: .library
        }
    }

    private var header: some View {
        CategoryHeader(title: title, icon: folderPath == nil ? category.icon : "folder", count: (results ?? scopedSongs).count,
                       selecting: selecting,
                       shuffle: { actions.playShuffled(results ?? [], source: playbackSource) },
                       play: { actions.playInOrder(results ?? [], source: playbackSource) },
                       search: { showsSearch = true; searchFocused = true },
                       select: { selecting.toggle(); if !selecting { selected.removeAll() } }) {
            Picker("Sort by", selection: $sort) {
                ForEach(LibrarySort.songs, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
            }
            Button(showsFilters ? "Hide filters" : "Show filters", systemImage: "line.3.horizontal.decrease") { showsFilters.toggle() }
            Button("Import music", systemImage: "plus") { router.showsImporter = true }
        }
    }

    @ViewBuilder private var recentCollections: some View {
        if !library.recentAlbums.isEmpty {
            Shelf(title: "Recently played albums") {
                ForEach(library.recentAlbums) { album in
                    AlbumTile(album: album) { router.open(.album(album.id)) }.frame(width: ArtworkSize.shelf)
                }
            }
        }
        if !library.recentPlaylists.isEmpty {
            Shelf(title: "Recently played playlists") {
                ForEach(library.recentPlaylists) { playlist in
                    PlaylistTile(playlist: playlist) { router.open(.playlist(playlist.id)) }.frame(width: ArtworkSize.shelf)
                }
            }
        }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Menu {
                    Picker("Date added", selection: $added) {
                        ForEach(SongAddedPeriod.allCases) { Text($0.description).tag($0) }
                    }
                } label: { SongsFilterLabel(title: added.label, symbol: "calendar.badge.clock") }
                Menu {
                    Picker("Genre", selection: $genre) {
                        Text("All genres").tag("")
                        Text("Untagged").tag(LibraryBrowse.untaggedGenre)
                        ForEach(genres, id: \.self) { Text($0).tag(SectionSearch.key($0)) }
                    }
                } label: { SongsFilterLabel(title: genreTitle, symbol: "guitars") }
                Menu {
                    Picker("Mood", selection: $mood) {
                        ForEach(LibraryMood.allCases, id: \.rawValue) { Text($0 == .all ? "All moods" : $0.label).tag($0) }
                    }
                } label: { SongsFilterLabel(title: mood == .all ? "Mood" : mood.label, symbol: "sparkles") }
            }
            if hasFilters {
                Button("Clear filters") { added = .any; genre = ""; mood = .all }
                    .font(.caption).frame(minHeight: 44)
            }
        }.padding(.horizontal, Spacing.gutter)
    }

    private var genreTitle: String {
        genre.isEmpty ? "Genre" : genre == LibraryBrowse.untaggedGenre ? "Untagged"
            : genres.first { SectionSearch.key($0) == genre } ?? "Genre"
    }

    private var selectionActions: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("\(selected.count) selected").font(.headline)
            HStack {
                Button("Select all") { selected.formUnion((results ?? []).map(\.id)) }
                Button("Clear") { selected.removeAll() }
            }.buttonStyle(.bordered)
            HStack {
                Button {
                    SearchHistoryStore.shared.remember(query, in: "songs")
                    router.songsForPlaylist = selectedSongs
                } label: { Label("Add to playlist", systemImage: "text.badge.plus") }
                .accessibilityIdentifier("songsAddToPlaylist")
                Button(role: .destructive) {
                    pendingDeletion = selectedSongs
                    confirmsDeletion = true
                } label: { Label("Delete", systemImage: "trash") }
                .accessibilityIdentifier("songsDeleteSelected")
            }.buttonStyle(.bordered).disabled(selectedSongs.isEmpty)
        }.padding(.horizontal, Spacing.gutter)
    }

    private func closeSearch() { searchFocused = false; query = ""; showsSearch = false }
}

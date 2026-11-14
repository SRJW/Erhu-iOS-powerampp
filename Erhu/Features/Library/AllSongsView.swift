import SwiftUI

/// Songs keeps amp's theme, with collection-wide play, focused tools and explicit bulk actions.
struct AllSongsView: View {
    var folderPath: String? = nil
    @Environment(LibraryStore.self) private var library
    @Environment(LibraryActions.self) private var actions
    @Environment(AppRouter.self) private var router
    @AppStorage("library.songs.sort") private var sort = LibrarySort.title.rawValue
    @State private var selecting = false
    @State private var selected = Set<Int64>()
    @State private var pendingDeletion: [Song] = []
    @State private var confirmsDeletion = false
    @State private var query = ""
    @State private var showsSearch = false
    @State private var showsFilters = true
    @State private var added = SongAddedPeriod.any
    @State private var genre = ""
    @State private var mood = LibraryMood.all
    @State private var results: [Song]?
    @State private var genres: [String] = []
    @FocusState private var searchFocused: Bool

    private var scopedSongs: [Song] {
        guard let folderPath else { return library.songs }
        return library.songs.filter { ($0.path as NSString).deletingLastPathComponent == folderPath }
    }
    private var title: String {
        folderPath.map { ($0 as NSString).lastPathComponent }.flatMap { $0.isEmpty ? nil : $0 } ?? "Songs"
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
        PlayerSongReveal(destination: folderPath.map(Route.songFolder) ?? .allSongs, songs: results ?? []) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    header
                    tools
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
                    if let results {
                        if hasFilters || !query.trimmed.isEmpty {
                            Text("\(results.count) \(results.count == 1 ? "match" : "matches")").font(.caption).foregroundStyle(.secondary)
                                .padding(.horizontal, Spacing.gutter)
                        }
                        SongList(songs: results, emptyMessage: scopedSongs.isEmpty ? "No songs found." : "No songs match these filters.",
                                 emptyIcon: "music.note", selection: selecting ? $selected : nil, showsFileDetails: true,
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

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("sectionBrowseTitle")
            Text("\(countLabel(scopedSongs.count, "song")) in \(folderPath == nil ? "your library" : "this folder")")
                .font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: Spacing.md) {
                SongsPlayButton(title: "Play All", symbol: "play.fill", filled: true) {
                    SearchHistoryStore.shared.remember(query, in: "songs")
                    actions.playInOrder(results ?? [], source: .library)
                }.accessibilityIdentifier("songsPlayAll")
                SongsPlayButton(title: "Shuffle", symbol: "shuffle") {
                    SearchHistoryStore.shared.remember(query, in: "songs")
                    actions.playShuffled(results ?? [], source: .library)
                }.accessibilityIdentifier("songsShuffle")
            }.disabled(selecting || (results ?? []).isEmpty)
        }.padding(.horizontal, Spacing.gutter)
    }

    private var tools: some View {
        HStack(spacing: Spacing.sm) {
            Button {
                selecting.toggle()
                if !selecting { selected.removeAll() }
            } label: { SongsToolLabel(title: selecting ? "Done" : "Select", symbol: "checklist", active: selecting) }
                .accessibilityIdentifier("songsSelect")
            Divider().frame(height: 36)
            Menu {
                Picker("Sort by", selection: $sort) {
                    ForEach(LibrarySort.songs, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
                }
            } label: { SongsToolLabel(title: "Sort", symbol: "arrow.up.arrow.down") }
            Button { showsFilters.toggle() } label: { SongsToolLabel(title: "Filter", symbol: "line.3.horizontal.decrease", active: hasFilters) }
            Divider().frame(height: 36)
            Button { showsSearch = true; searchFocused = true } label: { SongsToolLabel(title: "Search", symbol: "magnifyingglass", active: showsSearch) }
                .accessibilityIdentifier("sectionSearchButton")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Spacing.gutter)
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

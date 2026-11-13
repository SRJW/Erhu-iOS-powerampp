import SwiftUI
import Observation

/// A recently opened search result.
enum RecentSearchItem: Identifiable, Equatable {
    case song(Song)
    case album(Album)
    case artist(Artist)
    case playlist(Playlist)

    var id: String {
        switch self {
        case .song(let song): "song:\(song.id)"
        case .album(let album): "album:\(album.id)"
        case .artist(let artist): "artist:\(artist.id)"
        case .playlist(let playlist): "playlist:\(playlist.id)"
        }
    }
}

/// Library search (title / artist / album, accent- and case-insensitive) and its recent items.
@MainActor
@Observable
final class SearchStore {
    static let sectionLimit = 20
    private static let recentLimit = 15

    var query = "" {
        didSet { schedule() }
    }
    private(set) var songs: [Song] = []
    private(set) var albums: [Album] = []
    private(set) var artists: [Artist] = []
    private(set) var recents: [RecentSearchItem] = []

    private let library: LibraryStore
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var generation: UInt64 = 0

    init(library: LibraryStore) { self.library = library }

    private func schedule() {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .milliseconds(150))
            if !Task.isCancelled { await run() }
        }
    }

    func run() async {
        generation &+= 1
        let request = generation
        let text = query.trimmed
        let songs = library.songs, albums = library.albums, artists = library.artists
        let result = await Task.detached(priority: .userInitiated) {
            LibrarySearch.results(text, songs: songs, albums: albums, artists: artists)
        }.value
        guard !Task.isCancelled, request == generation, text == query.trimmed else { return }
        self.songs = result.songs; self.albums = result.albums; self.artists = result.artists
    }

    func remember(_ item: RecentSearchItem) {
        SearchHistoryStore.shared.remember(query, in: "library")
        recents.removeAll { $0.id == item.id }
        recents.insert(item, at: 0)
        recents = Array(recents.prefix(Self.recentLimit))
    }

    func forget(_ item: RecentSearchItem) { recents.removeAll { $0.id == item.id } }

    func clearRecents() { recents = [] }
}

/// Search over the library: artists, albums and songs as you type, recent items before you do.
struct SearchView: View {
    @Environment(SearchStore.self) private var search
    @Environment(LibraryStore.self) private var library
    @Environment(LibraryActions.self) private var actions
    @Environment(PlayerController.self) private var player
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var search = search
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if search.query.trimmed.isEmpty {
                        RecentSearchesView(scope: "library") { search.query = $0; focused = true }
                            .padding(.horizontal, Spacing.gutter)
                        if !search.recents.isEmpty || SearchHistoryStore.shared.entries("library").isEmpty { recents }
                    } else if search.songs.isEmpty && search.albums.isEmpty && search.artists.isEmpty {
                        EmptyState(message: "Nothing in your library matches \"\(search.query.trimmed)\".", systemImage: "magnifyingglass")
                    } else {
                        results
                    }
                }
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.lg)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .top, spacing: 0) {
                GlassSearchField(text: $search.query, prompt: "Songs, albums, artists", focused: $focused, close: { focused = false; router.showsSearch = false; dismiss() })
                    .padding(.horizontal, Spacing.gutter).padding(.vertical, Spacing.sm)
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { focused = true }
            .task(id: library.songs) { await search.run() }
            .modifier(ToolPageAppearance())
        }
    }

    @ViewBuilder private var results: some View {
        if !search.artists.isEmpty {
            Shelf(title: "Artists") {
                ForEach(search.artists) { artist in
                    ArtistTile(artist: artist) { open(.artist(artist)) }.frame(width: 112)
                }
            }
        }
        if !search.albums.isEmpty {
            Shelf(title: "Albums") {
                ForEach(search.albums) { album in
                    AlbumTile(album: album) { open(.album(album)) }.frame(width: 128)
                }
            }
        }
        if !search.songs.isEmpty {
            SectionHeading(title: "Songs")
            let songActions = router.songActions(actions)
            ForEach(Array(search.songs.enumerated()), id: \.element.id) { index, song in
                TrackRow(song: song, isCurrent: song.id == player.state.currentSong?.id, actions: songActions) {
                    search.remember(.song(song))
                    actions.play(search.songs, startIndex: index)
                }
            }
        }
    }

    @ViewBuilder private var recents: some View {
        if search.recents.isEmpty {
            EmptyState(message: "Search your songs, albums and artists.", systemImage: "magnifyingglass")
        } else {
            HStack {
                Text("Recent").font(.title3.weight(.bold))
                Spacer()
                Button("Clear") { search.clearRecents() }
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.vertical, Spacing.sm)
            ForEach(search.recents) { item in
                HStack(spacing: Spacing.md) {
                    Button { reopen(item) } label: { recentRow(item) }.buttonStyle(.plain)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button { search.forget(item) } label: {
                        Image(systemName: "xmark").foregroundStyle(.secondary).frame(width: 32, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove from recent")
                }
                .padding(.horizontal, Spacing.gutter)
                .padding(.vertical, Spacing.sm)
            }
        }
    }

    private func recentRow(_ item: RecentSearchItem) -> some View {
        HStack(spacing: Spacing.md) {
            Group {
                switch item {
                case .song(let song): SongArtworkView(song: song, maxPixels: 144)
                case .album(let album): AlbumArtworkView(albumId: album.id, maxPixels: 144)
                case .artist(let artist): ArtistArtworkView(artist: artist, fontSize: 18)
                case .playlist(let playlist): PlaylistCoverView(playlist: playlist)
                }
            }
            .frame(width: ArtworkSize.list, height: ArtworkSize.list)
            .clipShape(itemShape(item))
            VStack(alignment: .leading, spacing: 2) {
                Text(title(item)).font(.body.weight(.semibold)).lineLimit(1)
                Text(subtitle(item)).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: ArtworkSize.list)
        .contentShape(Rectangle())
    }

    private func itemShape(_ item: RecentSearchItem) -> AnyShape {
        if case .artist = item { return AnyShape(Circle()) }
        return AnyShape(RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
    }

    private func title(_ item: RecentSearchItem) -> String {
        switch item {
        case .song(let song): song.title
        case .album(let album): album.title
        case .artist(let artist): artist.name
        case .playlist(let playlist): playlist.name
        }
    }

    private func subtitle(_ item: RecentSearchItem) -> String {
        switch item {
        case .song(let song): "Song · \(song.artist)"
        case .album(let album): "Album · \(album.artist)"
        case .artist: "Artist"
        case .playlist(let playlist): "Playlist · \(countLabel(playlist.songCount, "song"))"
        }
    }

    private func reopen(_ item: RecentSearchItem) {
        switch item {
        case .song(let song):
            search.remember(item)
            actions.play([song], startIndex: 0)
        default:
            open(item)
        }
    }

    private func open(_ item: RecentSearchItem) {
        search.remember(item)
        dismiss()
        switch item {
        case .album(let album): router.open(.album(album.id))
        case .artist(let artist): router.open(.artist(artist.id))
        case .playlist(let playlist): router.open(.playlist(playlist.id))
        case .song: break
        }
    }
}

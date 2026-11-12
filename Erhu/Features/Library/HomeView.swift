import SwiftUI

/// Home shows radio, featured albums, recently played albums/playlists and all tracks. Shelves scroll
/// away with the tracks; each shelf scrolls sideways on its own.
struct HomeView: View {
    @State private var releases = ReleaseChecker.shared
    @Environment(\.vybeEnabled) private var vybeEnabled
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerController.self) private var player
    @Environment(LibraryActions.self) private var actions
    @Environment(AppRouter.self) private var router

    var body: some View {
        let songs = library.songs
        let hasSongs = !songs.isEmpty
        let hasShelves = hasSongs || !library.recentAlbums.isEmpty || !library.recentPlaylists.isEmpty
        let songActions = router.songActions(actions)
        let currentId = player.state.currentSong?.id
        LibraryRootScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if case .available(let release) = releases.state {
                    Button { router.open(.settingsPage(.about)) } label: {
                        Label("amp \(release.tag_name) is available", systemImage: "arrow.down.circle")
                            .font(.subheadline).padding(Spacing.lg)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                if vybeEnabled { RadioStationShelf() }
                shelves(showsRecentNote: hasSongs)
                if hasShelves { SectionHeading(title: "Tracks") }
                if songs.isEmpty {
                    EmptyState(message: library.isScanning ? "Scanning your music…" : "No songs yet. Add music with the Files app, Wi-Fi Transfer or the + button.",
                               systemImage: "house")
                } else {
                    ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                        TrackRow(song: song, isCurrent: song.id == currentId, actions: songActions) {
                            actions.play(songs, startIndex: index)
                        }
                    }
                }
            }
            .padding(.bottom, Spacing.lg)
        }
        .tracksLibraryScrolling()
        .refreshable { library.scan() }
    }

    @ViewBuilder
    private func shelves(showsRecentNote: Bool) -> some View {
        if !library.featuredAlbums.isEmpty {
            Shelf(title: "Featured Albums") {
                ForEach(library.featuredAlbums) { album in
                    AlbumTile(album: album) { router.open(.album(album.id)) }.frame(width: ArtworkSize.shelf)
                }
            }
            .padding(.bottom, Spacing.lg)
        }
        if !library.recentAlbums.isEmpty {
            Shelf(title: "Recently played albums") {
                ForEach(library.recentAlbums) { album in
                    AlbumTile(album: album) { router.open(.album(album.id)) }.frame(width: ArtworkSize.shelf)
                }
            }
            .padding(.bottom, Spacing.lg)
        } else if showsRecentNote {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeading(title: "Recently played albums")
                Text("Albums you play show up here.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Spacing.gutter)
            }
            .padding(.bottom, Spacing.lg)
        }
        if !library.recentPlaylists.isEmpty {
            Shelf(title: "Recently played playlists") {
                ForEach(library.recentPlaylists) { playlist in
                    PlaylistTile(playlist: playlist) { router.open(.playlist(playlist.id)) }.frame(width: ArtworkSize.shelf)
                }
            }
            .padding(.bottom, Spacing.lg)
        }
    }
}

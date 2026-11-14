import PhotosUI
import SwiftUI

/// The shared top of a collection page: big cover, title, subtitle, facts, Play / Shuffle.
struct CollectionHeader<Cover: View>: View {
    let title: String
    let subtitle: String?
    let facts: String
    var note: String?
    var coverShape: AnyShape = AnyShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
    var coverInset: CGFloat = 64
    let canPlay: Bool
    let onPlay: () -> Void
    let onShuffle: () -> Void
    @ViewBuilder let cover: () -> Cover
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: Spacing.xs) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay { cover() }
                .clipShape(coverShape)
                .frame(maxWidth: ArtworkSize.heroMax)
                .padding(.horizontal, coverInset)
                .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
                .padding(.bottom, Spacing.lg)
            Text(title).font(.title.weight(.bold)).multilineTextAlignment(.center).lineLimit(2)
            if let subtitle { Text(subtitle).font(.headline).foregroundStyle(palette.onSurface).lineLimit(1) }
            if let note { Text(note).font(.caption).foregroundStyle(palette.onSurfaceVariant).multilineTextAlignment(.center) }
            Text(facts).font(.caption).foregroundStyle(palette.onSurfaceVariant).lineLimit(1)
            HStack(spacing: Spacing.sm) {
                Button(action: onPlay) {
                    Label("Play", systemImage: "play.fill").frame(maxWidth: .infinity).foregroundStyle(palette.onFilledButton)
                }
                .modifier(PaletteFilledButton())
                .tint(palette.filledButton)
                Button(action: onShuffle) {
                    Label("Shuffle", systemImage: "shuffle").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
            .disabled(!canPlay)
            .padding(.horizontal, Spacing.xxl)
            .padding(.vertical, Spacing.md)
        }
        .padding(.horizontal, Spacing.heroGutter)
        .padding(.top, Spacing.sm)
    }
}

/// "2018 · 12 songs · 43 min"; unknown parts are left out.
func collectionFacts(year: Int? = nil, songs: [Song]) -> String {
    let minutes = songs.reduce(Int64(0)) { $0 + $1.durationMs } / 60_000
    let duration: String? = minutes <= 0 ? nil : minutes < 60 ? "\(minutes) min" : "\(minutes / 60) hr \(minutes % 60) min"
    let yearText = year.flatMap { (1900...2099).contains($0) ? String($0) : nil }
    return [yearText, countLabel(songs.count, "song"), duration].compactMap { $0 }.joined(separator: " · ")
}

/// An album: cover, facts (and "Lossless" when any track is), Play / Shuffle, its tracks by number.
struct AlbumDetailView: View {
    @Environment(\.radioAvailable) private var radioAvailable
    let albumId: Int64
    @Environment(LibraryStore.self) private var library
    @Environment(LibraryActions.self) private var actions
    @Environment(AppRouter.self) private var router
    @State private var songs: [Song] = []
    @State private var artworkTarget: ArtworkTarget?

    var body: some View {
        let origin = CollectionRef.album(albumId)
        PlayerSongReveal(destination: .album(albumId), songs: songs) {
            ScrollView {
                if let album = library.album(albumId) {
                    let facts = collectionFacts(year: album.year, songs: songs)
                    VStack(spacing: 0) {
                        CollectionHeroHeader(title: album.title, subtitle: album.artist, facts: songs.contains(where: \.isLossless) ? "\(facts) · Lossless" : facts,
                                         canPlay: !songs.isEmpty, onPlay: { actions.playInOrder(songs, origin: origin) },
                                         onShuffle: { actions.playShuffled(songs, origin: origin) }) {
                            AlbumArtworkView(albumId: albumId, maxPixels: 1200)
                        }
                        TransitionStudioRow(collection: origin).padding(.bottom, Spacing.sm)
                        ScopedTagRepairSummary(songs: songs)
                        CollectionTransitionTrackList(collection: origin,
                                                      tracks: songs.map { StudioTrack(song: $0, occurrence: TrackOccurrence($0.id)) },
                                                      showTrackNumbers: true)
                    }
                } else {
                    EmptyState(message: "This album is no longer in your library.", systemImage: "square.stack")
                }
            }
        }
        .tracksLibraryScrolling()
        .ignoresSafeArea(.container, edges: .top)
        .toolbarBackground(.hidden, for: .navigationBar)
        .modifier(CollectionTopEdgeEffect())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Menu {
                Button { songs.reversed().forEach { actions.playNext($0) } } label: { Label("Play next", systemImage: "text.line.first.and.arrowtriangle.forward") }
                Button { songs.forEach { actions.addToQueue($0) } } label: { Label("Add to queue", systemImage: "text.badge.plus") }
                if radioAvailable { Button { router.open(.radio(.album(albumId))) } label: { Label("Browse radio", systemImage: "dot.radiowaves.left.and.right") } }
                Button { router.songsForPlaylist = songs } label: { Label("Add to playlist", systemImage: "music.note.list") }
                Button { actions.fixTags(songs) } label: {
                    Label("Fix tags online", systemImage: "wand.and.stars")
                }
                if let album = library.album(albumId) {
                    Button { artworkTarget = .album(album) } label: { Label("Find a cover", systemImage: "photo") }
                }
            } label: { Image(systemName: "ellipsis.circle") }
            .accessibilityLabel("Album options")
        }
        .sheet(item: $artworkTarget) { ArtworkPickerSheet(target: $0) }
        .task(id: library.songs) { songs = (try? library.database.songsOfAlbum(albumId)) ?? [] }
        .background { CollectionPageBackground() }
        .collectionArtworkTheme(.track(library.albumCoverSong[albumId]?.url))
    }
}

/// An artist: photo or monogram, Play / Shuffle, albums split into Albums, EPs and Singles, then
/// features, credited songs and their own tracks.
struct ArtistDetailView: View {
    @Environment(\.radioAvailable) private var radioAvailable
    let artistId: Int64
    @Environment(LibraryStore.self) private var library
    @Environment(LibraryActions.self) private var actions
    @Environment(AppRouter.self) private var router
    @State private var albums: [Album] = []
    @State private var primary: [Song] = []
    @State private var featured: [Song] = []
    @State private var unverified: [Song] = []
    @State private var artworkTarget: ArtworkTarget?

    var body: some View {
        ScrollView {
            if let artist = library.artist(artistId) {
                let all = primary.isEmpty ? featured : primary
                LazyVStack(alignment: .leading, spacing: 0) {
                    CollectionHeroHeader(title: artist.name, subtitle: nil,
                                     facts: "\(countLabel(artist.songCount, "song")) · \(countLabel(artist.albumCount, "album"))",
                                     canPlay: !all.isEmpty,
                                     onPlay: { actions.playInOrder(all, source: .artist(artistId)) },
                                     onShuffle: { actions.playShuffled(all, source: .artist(artistId)) }) {
                        ArtistArtworkView(artist: artist, fontSize: 96, maxPixels: 1200)
                    }
                    ScopedTagRepairSummary(songs: primary + featured + unverified)
                    albumRow("Albums", albums.filter { $0.songCount >= 7 })
                    albumRow("EPs", albums.filter { (3...6).contains($0.songCount) })
                    albumRow("Singles", albums.filter { (1...2).contains($0.songCount) })
                    songSection("Features", featured)
                    songSection("Credited", unverified)
                    songSection("Tracks", primary, numbers: true)
                    if primary.isEmpty && featured.isEmpty {
                        EmptyState(message: "No tracks found for this artist.")
                    }
                }
            } else {
                EmptyState(message: "This artist is no longer in your library.", systemImage: "person")
            }
        }
        .tracksLibraryScrolling()
        .ignoresSafeArea(.container, edges: .top)
        .toolbarBackground(.hidden, for: .navigationBar)
        .modifier(CollectionTopEdgeEffect())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Menu {
                Button { primary.reversed().forEach { actions.playNext($0) } } label: { Label("Play next", systemImage: "text.line.first.and.arrowtriangle.forward") }
                Button { primary.forEach { actions.addToQueue($0) } } label: { Label("Add to queue", systemImage: "text.badge.plus") }
                Button { actions.fixTags(primary + featured + unverified) } label: { Label("Fix tags online", systemImage: "wand.and.stars") }
                if radioAvailable { Button { router.open(.radio(.artist(artistId))) } label: { Label("Browse radio", systemImage: "dot.radiowaves.left.and.right") } }
                if let artist = library.artist(artistId) {
                    Button { artworkTarget = .artist(artist) } label: { Label("Find a photo", systemImage: "person.crop.square") }
                    if artist.artworkPath != nil {
                        Button(role: .destructive) { AppServices.shared.artwork.removePhoto(artist) } label: {
                            Label("Remove chosen photo", systemImage: "trash")
                        }
                    }
                }
            } label: { Image(systemName: "ellipsis.circle") }
            .accessibilityLabel("Artist options")
        }
        .sheet(item: $artworkTarget) { ArtworkPickerSheet(target: $0) }
        .task(id: library.songs) { load() }
        .background { CollectionPageBackground() }
        .collectionArtworkTheme(.image(library.artist(artistId)?.artworkPath.map { URL(fileURLWithPath: LibraryPaths.resolveImage($0)) }))
    }

    private func load() {
        let db = library.database
        albums = (try? db.albumsOfArtist(artistId)) ?? []
        primary = (try? db.songsOfArtist(artistId, role: .primary)) ?? []
        featured = (try? db.songsOfArtist(artistId, role: .featured)) ?? []
        if let key = library.artist(artistId)?.artistKey, !key.isEmpty {
            unverified = (try? db.unverifiedSongs(artistKey: key)) ?? []
        }
    }

    @ViewBuilder
    private func albumRow(_ title: String, _ albums: [Album]) -> some View {
        if !albums.isEmpty {
            Shelf(title: title) {
                ForEach(albums) { album in
                    AlbumTile(album: album) { router.open(.album(album.id)) }.frame(width: 128)
                }
            }
            .padding(.bottom, Spacing.sm)
        }
    }

    @ViewBuilder
    private func songSection(_ title: String, _ songs: [Song], numbers: Bool = false) -> some View {
        if !songs.isEmpty {
            SectionHeading(title: title)
            SongList(songs: songs, showTrackNumbers: numbers, source: .artist(artistId))
        }
    }
}

/// A playlist: cover, facts, Play / Shuffle, its songs; rename, delete, remove a song.
struct PlaylistDetailView: View {
    @Environment(\.radioAvailable) private var radioAvailable
    let playlistId: Int64
    @Environment(LibraryStore.self) private var library
    @Environment(LibraryActions.self) private var actions
    @Environment(PlayerController.self) private var player
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [PlaylistEntry] = []
    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmingDelete = false
    @State private var coverItem: PhotosPickerItem?
    @State private var choosingCover = false

    var body: some View {
        let origin = CollectionRef.playlist(playlistId)
        let songs = entries.map(\.song)
        let slots = entries.map(\.position)
        let songActions = playlistSongActions()
        PlayerSongReveal(destination: .playlist(playlistId), songs: songs) {
            ScrollView {
                if let playlist = library.playlist(playlistId) {
                    LazyVStack(spacing: 0) {
                        CollectionHeader(title: playlist.name, subtitle: nil, facts: collectionFacts(songs: songs), canPlay: !songs.isEmpty,
                                         onPlay: { actions.playInOrder(songs, origin: origin, slots: slots) },
                                         onShuffle: { actions.playShuffled(songs, origin: origin, slots: slots) }) { PlaylistCoverView(playlist: playlist) }
                        if songs.count > 1 { TransitionStudioRow(collection: origin).padding(.bottom, Spacing.sm) }
                        if songs.isEmpty {
                            EmptyState(message: "This playlist is empty. Add songs from any song's menu.", systemImage: "music.note.list")
                        }
                        ScopedTagRepairSummary(songs: songs)
                        CollectionTransitionTrackList(collection: origin,
                            tracks: entries.map { StudioTrack(song: $0.song, occurrence: TrackOccurrence($0.song.id, $0.position)) },
                            songActions: songActions)
                    }
                } else {
                    EmptyState(message: "This playlist no longer exists.", systemImage: "music.note.list")
                }
            }
        }
        .tracksLibraryScrolling()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Menu {
                if radioAvailable {
                    Button { router.open(.radio(.song(songs.first?.id ?? 0))) } label: { Label("Browse radio", systemImage: "dot.radiowaves.left.and.right") }
                        .disabled(songs.isEmpty)
                }
                Button {
                    newName = library.playlist(playlistId)?.name ?? ""
                    renaming = true
                } label: { Label("Rename", systemImage: "pencil") }
                Button { actions.fixTags(songs) } label: { Label("Fix tags online", systemImage: "wand.and.stars") }
                Button { choosingCover = true } label: { Label("Choose cover", systemImage: "photo") }
                if let playlist = library.playlist(playlistId), playlist.artworkPath != nil {
                    Button { AppServices.shared.artwork.removePlaylistCover(playlist) } label: { Label("Remove cover", systemImage: "photo.badge.minus") }
                }
                Button(role: .destructive) { confirmingDelete = true } label: { Label("Delete playlist", systemImage: "trash") }
            } label: { Image(systemName: "ellipsis.circle") }
            .accessibilityLabel("Playlist options")
        }
        .photosPicker(isPresented: $choosingCover, selection: $coverItem, matching: .images)
        .onChange(of: coverItem) { _, item in
            guard let item, let playlist = library.playlist(playlistId) else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    do {
                        try AppServices.shared.artwork.setPlaylistCover(data, playlist: playlist)
                    } catch {
                        actions.show("Couldn't save the cover: \(error.localizedDescription)")
                    }
                }
                coverItem = nil
            }
        }
        .alert("Rename playlist", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Rename") { try? library.database.renamePlaylist(playlistId, name: newName.trimmed) }
        }
        .confirmationDialog("Delete this playlist?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                try? library.database.deletePlaylist(playlistId)
                dismiss()
            }
        } message: {
            Text("The songs stay in your library.")
        }
        .task(id: library.playlists) { entries = (try? library.database.playlistEntries(playlistId)) ?? [] }
    }

    private func playlistSongActions() -> SongActions {
        var songActions = router.songActions(actions, source: .playlist(playlistId))
        songActions.removeFromPlaylist = { remove($0) }
        return songActions
    }

    private func remove(_ song: Song) {
        try? library.database.removeSong(song.id, fromPlaylist: playlistId)
    }
}

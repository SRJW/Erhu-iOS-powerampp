import SwiftUI

struct AlbumsView: View {
    var body: some View { EntityCategoryView(category: .albums) }
}

/// The single library root; migrate the previous saved section order without hiding new categories.
struct LibraryOverviewView: View {
    @Environment(AppRouter.self) private var router
    @Environment(LibraryStore.self) private var library
    @State private var releases = ReleaseChecker.shared
    @AppStorage("library.overview.sectionOrder") private var storedOrder = "songs,albums,artists,playlists,mostPlayed,recentlyPlayed,recentlyAdded,favorites,folders,albumArtists,radio"
    @State private var showsOrder = false
    @State private var editingOrder: [LibraryCategory] = []
    var body: some View {
        LibraryRootScrollView {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                if case .available(let release) = releases.state {
                    Button { router.open(.settingsPage(.about)) } label: {
                        Label("amp \(release.tag_name) is available", systemImage: "arrow.down.circle")
                            .padding(Spacing.lg)
                    }
                }
                ForEach(LibraryCategory.ordered(storedOrder)) { category in
                    Button { router.open(category == .songs ? .allSongs : .category(category)) } label: {
                        HStack(spacing: Spacing.lg) {
                            Image(systemName: category.icon).font(.title2).frame(width: 36)
                            Text(category.title).font(.headline)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }.frame(minHeight: 56).padding(.horizontal, Spacing.gutter).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("libraryCategory.\(category.rawValue)")
                }
            }.padding(.vertical, Spacing.md)
        }
        .refreshable { library.scan() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Import music", systemImage: "plus") { router.showsImporter = true }
                    Button("Wi-Fi Transfer", systemImage: "wifi") { router.open(Tool.wifiTransfer) }
                    Button("Reorder categories", systemImage: "arrow.up.arrow.down") {
                        editingOrder = LibraryCategory.ordered(storedOrder); showsOrder = true
                    }
                } label: { Image(systemName: "ellipsis").rotationEffect(.degrees(90)).frame(width: 44, height: 44) }
                .accessibilityLabel("Library options")
            }
        }
        .sheet(isPresented: $showsOrder) {
            NavigationStack {
                List {
                    ForEach(editingOrder) { Text($0.title) }
                        .onMove { source, destination in
                            editingOrder.move(fromOffsets: source, toOffset: destination)
                            storedOrder = editingOrder.map(\.rawValue).joined(separator: ",")
                        }
                }
                .environment(\.editMode, .constant(.active))
                .navigationTitle("Library order")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Reset") { editingOrder = LibraryCategory.allCases; storedOrder = editingOrder.map(\.rawValue).joined(separator: ",") }
                    }
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { showsOrder = false } }
                }
            }
        }
    }
}

struct LibraryShelfView: View {
    let shelf: LibraryShelf
    @ViewBuilder var body: some View {
        switch shelf {
        case .favorites: AllSongsView(category: .favorites)
        case .artists: EntityCategoryView(category: .artists)
        case .playlists: EntityCategoryView(category: .playlists)
        }
    }
}

/// A plain list of tracks that plays from the tapped one.
struct SongList: View {
    let songs: [Song]
    var emptyMessage = ""
    var emptyIcon = "music.note"
    var origin: CollectionRef?
    var showTrackNumbers = false
    var source: PlaybackSource?
    var selection: Binding<Set<Int64>>? = nil
    var showsFileDetails = false
    var onPlay: (() -> Void)? = nil
    var onPlaySong: ((Song) -> Void)? = nil
    @Environment(LibraryActions.self) private var actions
    @Environment(PlayerController.self) private var player
    @Environment(AppRouter.self) private var router

    var body: some View {
        let songActions = router.songActions(actions, source: source ?? origin.map { PlaybackSource($0) })
        let currentId = player.state.currentSong?.id
        LazyVStack(spacing: 0) {
            if songs.isEmpty {
                EmptyState(message: emptyMessage, systemImage: emptyIcon)
            }
            ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                Group {
                    if let selection {
                        Button {
                            if selection.wrappedValue.contains(song.id) { selection.wrappedValue.remove(song.id) }
                            else { selection.wrappedValue.insert(song.id) }
                        } label: {
                            HStack(spacing: 0) {
                                Image(systemName: selection.wrappedValue.contains(song.id) ? "checkmark.circle.fill" : "circle")
                                    .frame(width: 44, height: 44)
                                TrackRow(song: song, isCurrent: song.id == currentId, showsFileDetails: showsFileDetails, showsActions: false, actions: songActions, onTap: {})
                                    .allowsHitTesting(false).accessibilityHidden(true)
                            }.contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(SongRowText.accessibilityLabel(song, includingFileDetails: showsFileDetails))
                        .accessibilityValue(selection.wrappedValue.contains(song.id) ? "Selected" : "Not selected")
                    } else {
                        TrackRow(song: song, isCurrent: song.id == currentId, showTrackNumber: showTrackNumbers, displayTrackNumber: showTrackNumbers ? index + 1 : nil, showsFileDetails: showsFileDetails, actions: songActions) {
                            onPlay?()
                            onPlaySong?(song)
                            actions.play(songs, startIndex: index, origin: origin, source: source)
                        }
                    }
                }
                .id("amp-song-\(song.id)")
            }
        }
    }
}

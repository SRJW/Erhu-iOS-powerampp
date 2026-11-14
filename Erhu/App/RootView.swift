import SwiftUI
import UniformTypeIdentifiers

/// Persistent section stacks, full player and tools share the same bottom navigation.
struct RootView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerController.self) private var player
    @Environment(LibraryActions.self) private var actions
    @Environment(AppRouter.self) private var router
    @Environment(SoundStore.self) private var sound
    @Environment(FixTagsStore.self) private var fixTags
    @Environment(WifiTransferStore.self) private var transfer
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.palette) private var palette
    @Environment(\.playerReduceMotion) private var reduceMotion
    @State private var releases = ReleaseChecker.shared
    @State private var chrome = LibraryChromeState()
    @State private var playerMotion = PlayerDragState()
    @State private var visualBudget = VisualWorkBudget.current
    var body: some View {
        @Bindable var router = router
        @Bindable var library = library
        ZStack(alignment: .bottom) {
            palette.background.ignoresSafeArea()
            sectionStack(router.section)
                .id(router.section)
                .allowsHitTesting(!router.showsNowPlaying && router.presentedTool == nil)
                .accessibilityHidden(router.showsNowPlaying || router.presentedTool != nil)
            if !router.showsNowPlaying && router.presentedTool == nil {
                AppBottomBar().zIndex(2)
            }
            if let message = actions.message, !router.showsNowPlaying {
                LibraryChromeToast(text: message, id: actions.messageID, hasSong: player.state.currentSong != nil)
                    .zIndex(2)
            }
        }
        .overlay {
            GeometryReader { geometry in
                ZStack {
                    if playerMotion.isPresented && router.presentedTool == nil {
                        PlayerPresentation(drag: playerMotion)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .allowsHitTesting(router.presentedTool == nil)
                            .accessibilityHidden(router.presentedTool != nil)
                            .transition(.identity)
                            .zIndex(1)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .onChange(of: geometry.size, initial: true) { _, size in playerMotion.travel = max(size.height * 0.65, 240) }
            }
            .ignoresSafeArea()
            .allowsHitTesting(router.showsNowPlaying && router.presentedTool == nil)
        }
        .overlay {
            if let tool = router.presentedTool { toolScreen(tool).transition(.opacity) }
        }
        .overlay { if router.showsDrawer { AppMenu().transition(.opacity) } }
        .animation(reduceMotion ? nil : .easeInOut(duration: AppNavigationMetrics.duration), value: router.presentedTool)
        .animation(reduceMotion ? .linear(duration: 0.12) : .easeInOut(duration: 0.28), value: router.section)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: router.showsDrawer)
        .coordinateSpace(name: PlayerArtworkSpace.root)
        .onChange(of: router.showsNowPlaying, initial: true) { _, shown in
            playerMotion.setPresented(shown, reduceMotion: reduceMotion)
        }
        .animation(.easeInOut(duration: 0.2), value: actions.message)
        .environment(chrome)
        .environment(playerMotion)
        .environment(\.visualWorkBudget, visualBudget)
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange).receive(on: RunLoop.main)) { _ in visualBudget = .current }
        .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification).receive(on: RunLoop.main)) { _ in visualBudget = .current }
        .onChange(of: router.section) { _, _ in chrome.expand(reduceMotion: reduceMotion) }
        .onChange(of: router.showsSearch) { _, _ in chrome.expand(reduceMotion: reduceMotion) }
        .onChange(of: router.paths[router.section]?.count) { _, _ in chrome.expand(reduceMotion: reduceMotion) }
        .routerSheets(active: !router.showsNowPlaying || router.presentedTool != nil)
        .alert("New playlist", isPresented: $router.showsNewPlaylist) { NewPlaylistAlert() }
        .fileImporter(isPresented: $router.showsImporter, allowedContentTypes: [.audio, UTType(importedAs: "org.xiph.ogg")], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { library.importFiles(urls) }
        }
        .alert("Something went wrong", isPresented: $library.isShowingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(library.errorMessage ?? "")
        }
        .fullScreenCover(isPresented: Binding(get: { !settings.introductionCompleted }, set: { if !$0 { settings.introductionCompleted = true } })) {
            IntroductionView(firstLaunch: true)
        }
        .onChange(of: fixTags.isRunning) { wasRunning, running in
            guard wasRunning, !running, !fixTags.inPlaceScope.isEmpty else { return }
            let items = fixTags.queue.filter { fixTags.inPlaceScope.contains($0.id) }
            let fixed = items.filter { $0.status == .done }.count
            let review = items.filter { $0.status != .done && $0.status != .unchanged }.count
            actions.show("Tag repair: \(fixed) fixed, \(review) need review. Results are available on the collection page.")
        }
        .onChange(of: player.playbackError) { _, message in if let message { library.report(message) } }
        .sheet(item: Binding(get: {
            settings.introductionCompleted && !router.showsNowPlaying && !router.showsSearch && !router.showsDrawer ? releases.prompt : nil
        }, set: { if $0 == nil { releases.dismissPrompt() } })) { release in
            AppUpdatePrompt(release: release, checker: releases)
        }
        .onAppear { library.scan(); Task { await releases.checkOnOpen() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { library.scan(); Task { await releases.checkOnOpen() } }
            if phase == .background {
                transfer.stop(.backgrounded)
                player.persistNow()
                sound.persistNow()
            }
        }
    }

    private func sectionStack(_ section: LibrarySection) -> some View {
        NavigationStack(path: router.binding(for: section)) {
            sectionRoot(section)
                .navigationTitle(section.label)
                .navigationDestination(for: Route.self) { route in destination(route) }
                .safeAreaInset(edge: .bottom) { Color.clear.frame(height: chromeHeight) }
        }
        .environment(\.artworkSection, section)
    }

    @ViewBuilder
    private func sectionRoot(_ section: LibrarySection) -> some View {
        switch section {
        case .library: LibraryOverviewView()
        case .equalizer: EqualizerView()
        case .search: SearchView()
        }
    }

    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        Group {
            switch route {
            case .album(let id): AlbumDetailView(albumId: id)
            case .artist(let id): ArtistDetailView(artistId: id)
            case .playlist(let id): PlaylistDetailView(playlistId: id)
            case .radio(let seed): RadioStationView(seed: seed)
            case .shelf(let shelf): LibraryShelfView(shelf: shelf)
            case .allSongs: AllSongsView().navigationBarBackButtonHidden().toolbar { categoryBack }
            case .category(let category):
                Group {
                    switch category {
                    case .songs, .mostPlayed, .recentlyPlayed, .recentlyAdded, .favorites: AllSongsView(category: category)
                    default: EntityCategoryView(category: category)
                    }
                }.navigationBarBackButtonHidden().toolbar { categoryBack }
            case .songFolder(let path): AllSongsView(folderPath: path)
            case .tool(let tool): ToolView(tool: tool).tracksLibraryScrolling(usesUIKit: true)
            case .settingsPage(let page): SettingsDestinationView(page: page).tracksLibraryScrolling(usesUIKit: true)
            case .transitionStudio(let collection): TransitionStudioView(collection: collection).tracksLibraryScrolling(usesUIKit: true)
            }
        }
        .toolbar(.visible, for: .navigationBar)
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: router.presentedTool == nil ? chromeHeight : 0) }
    }

    @ToolbarContentBuilder private var categoryBack: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { router.activate(.library) } label: { Image(systemName: "chevron.up").frame(width: 44, height: 44) }
                .accessibilityLabel("Back to Library")
        }
    }

    private var chromeHeight: CGFloat { AppNavigationMetrics.reservedHeight }

    private func toolScreen(_ tool: Tool) -> some View {
        @Bindable var router = router
        return NavigationStack(path: $router.toolPath) {
            ToolView(tool: tool)
                .navigationDestination(for: Route.self) { route in
                    destination(route).toolbar { closeTool }
                }
                .toolbar { closeTool }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { AppBottomBar() }
        .background(palette.background.ignoresSafeArea())
    }

    @ToolbarContentBuilder private var closeTool: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { router.presentedTool = nil } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                .accessibilityLabel("Close tool").accessibilityIdentifier("closeTool")
        }
    }

}

/// Only this small overlay observes the animated chrome height, not the library screen tree.
private struct LibraryChromeToast: View {
    let text: String
    let id: UUID
    let hasSong: Bool
    @Environment(LibraryChromeState.self) private var chrome

    var body: some View {
        LibraryActionToast(text: text, id: id)
            .padding(.bottom, AppNavigationMetrics.reservedHeight)
    }
}

extension View {
    /// The song sheets anyone can ask the router for, presented by whichever screen is on top
    /// ([active]): the root, or Now Playing over it (a sheet from the root would open behind it).
    func routerSheets(active: Bool) -> some View { modifier(RouterSheets(active: active)) }
}

private struct RouterSheets: ViewModifier {
    @Environment(LibraryActions.self) private var actions
    let active: Bool
    @Environment(AppRouter.self) private var router

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Delete from device?", isPresented: Binding(
                get: { active && actions.songPendingDeletion != nil },
                set: { if active && !$0 { actions.songPendingDeletion = nil } }
            ), titleVisibility: .visible, presenting: actions.songPendingDeletion) { song in
                Button("Delete from device", role: .destructive) { actions.deleteFromDevice(song) }
                Button("Cancel", role: .cancel) {}
            } message: { song in
                Text("Permanently delete “\(song.title)” from amp's folder in Files, the library and playlists? This cannot be undone. Separate copies elsewhere are not deleted.")
            }
            .sheet(item: Binding(get: { active ? router.songsForPlaylist.map(SongBatch.init) : nil }, set: { router.songsForPlaylist = $0?.songs })) { batch in
                AddToPlaylistSheet(songs: batch.songs)
            }
            .sheet(item: Binding(get: { active ? router.songForDetails : nil }, set: { router.songForDetails = $0 })) { song in
                SongDetailsSheet(song: song)
            }
            .sheet(item: Binding(get: { active ? router.songForTagEdit : nil }, set: { router.songForTagEdit = $0 })) { song in
                EditTagsSheet(song: song)
            }
    }
}

/// Songs being added to a playlist (identifiable for the sheet).
private struct SongBatch: Identifiable {
    let songs: [Song]
    var id: [Int64] { songs.map(\.id) }
}

/// Pick a playlist for [songs], or create one with them.
struct AddToPlaylistSheet: View {
    let songs: [Song]
    @Environment(LibraryStore.self) private var library
    @Environment(LibraryActions.self) private var actions
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""
    @State private var creating = false

    var body: some View {
        NavigationStack {
            List {
                Button { creating = true } label: { Label("New playlist", systemImage: "plus") }
                ForEach(library.playlists) { playlist in
                    Button {
                        actions.add(songs, to: playlist)
                        dismiss()
                    } label: {
                        HStack(spacing: Spacing.md) {
                            PlaylistCoverView(playlist: playlist)
                                .frame(width: ArtworkSize.compact, height: ArtworkSize.compact)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
                            VStack(alignment: .leading) {
                                Text(playlist.name).foregroundStyle(.primary)
                                Text(countLabel(playlist.songCount, "song")).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle(songs.count == 1 ? "Add \"\(songs[0].title)\"" : "Add \(countLabel(songs.count, "song"))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Cancel") { dismiss() } }
            .alert("New playlist", isPresented: $creating) {
                TextField("Name", text: $newName)
                Button("Cancel", role: .cancel) {}
                Button("Create") {
                    actions.createPlaylist(newName, songs: songs)
                    dismiss()
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// The "New playlist" dialog's field and buttons.
private struct NewPlaylistAlert: View {
    @Environment(LibraryActions.self) private var actions
    @State private var name = ""

    var body: some View {
        TextField("Name", text: $name)
        Button("Cancel", role: .cancel) {}
        Button("Create") { actions.createPlaylist(name) }
    }
}

/// What the library knows about a song: its tags and its file.
struct SongDetailsSheet: View {
    let song: Song
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: Spacing.md) {
                        SongArtworkView(song: song, maxPixels: 300)
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
                        VStack(alignment: .leading) {
                            Text(song.title).font(.headline)
                            Text(song.artist).foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Tags") {
                    row("Title", song.title)
                    row("Artist", song.artist)
                    row("Album", song.album)
                    row("Track", song.trackNumber > 0 ? "\(song.trackNumber)" : nil)
                    row("Disc", song.discNumber > 0 ? "\(song.discNumber)" : nil)
                    row("Year", song.year > 0 ? "\(song.year)" : nil)
                    row("Genre", song.genre)
                    row("BPM", song.bpm.map(String.init))
                    row("Composer", song.composer)
                }
                Section("File") {
                    row("Duration", formatDuration(song.durationMs))
                    row("Format", song.codec)
                    row("Sample rate", song.sampleRate > 0 ? String(format: "%.1f kHz", Double(song.sampleRate) / 1000) : nil)
                    row("Bit rate", song.bitrate > 0 ? "\(song.bitrate / 1000) kbps" : nil)
                    row("Channels", song.channels > 0 ? "\(song.channels)" : nil)
                    row("Size", song.fileSize > 0 ? ByteCountFormatter.string(fromByteCount: song.fileSize, countStyle: .file) : nil)
                    row("Path", song.path)
                }
            }
            .navigationTitle("Music information")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
        }
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String?) -> some View {
        if let value, !value.isBlank {
            LabeledContent(label) { Text(value).multilineTextAlignment(.trailing).textSelection(.enabled) }
        }
    }
}

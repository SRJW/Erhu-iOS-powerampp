import SwiftUI

/// Full-bleed artwork player with waveform transport and compact library navigation.
struct NowPlayingView: View {
    @Environment(\.vybeEnabled) private var vybeEnabled
    @Environment(PlayerController.self) private var player
    @Environment(LibraryActions.self) private var actions
    @Environment(MixStore.self) private var mixes
    @Environment(AppRouter.self) private var router
    @Environment(LibraryStore.self) private var library
    @Environment(\.palette) private var palette
    @Environment(\.playerReduceMotion) private var reduceMotion
    @State private var artworkTarget: ArtworkTarget?
    let drag: PlayerDragState
    @State private var showsQueue = false
    @State private var showsLyrics = false
    @State private var showsMarks = false
    @State private var showsVisualizer = false
    @State private var showsEqualizer = false
    @State private var showsAudioDetails = false
    @GestureState private var headerPullActive = false

    var body: some View {
        let state = player.state
        GeometryReader { geometry in
            if let current = state.currentSong {
                let song = library.songs.first(where: { $0.id == current.id }) ?? current
                VStack(spacing: 0) {
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(pullGesture)
                        .accessibilityAction(named: "Close player") { close() }
                    VStack(spacing: 10) {
                        Text(song.title)
                            .accessibilityIdentifier("nowPlayingTitle")
                            .font(.system(size: 22, weight: .bold))
                            .lineLimit(2)
                        Text("\(song.artist) - \(song.album)")
                            .font(.system(size: 15, weight: .bold))
                            .lineLimit(2)
                    }
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 14)
                    referenceOptions(song, state: state)
                        .padding(.horizontal, 24)
                    ProgressSection(song: song) { controls(state) }
                        .frame(height: min(geometry.size.height * 0.21, 180))
                        .padding(.horizontal, 10)
                    Button { showsAudioDetails = true } label: {
                        Text(audioSummary(song))
                            .font(.system(size: 10, weight: .bold))
                            .lineLimit(1)
                            .padding(.vertical, 8)
                    }
                    referenceNavigation
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                }
                .foregroundStyle(.white)
            } else {
                EmptyState(message: "Nothing is playing. Pick a song from your library.", systemImage: "music.note")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(PlayerForegroundMotion(drag: drag))
        .modifier(PlayerChromeFade())
        .onChange(of: headerPullActive) { _, active in
            if !active { drag.cancelGesture(reduceMotion: reduceMotion) }
        }
        .onChange(of: drag.isMoving, initial: true) { _, active in player.setVisualMotion(.presentation, active: active) }
        .onDisappear {
            player.setVisualMotion(.presentation, active: false)
            player.setVisualMotion(.carousel, active: false)
        }
        .background(backdrop(state.currentSong).ignoresSafeArea().modifier(PlayerBackdropFade(drag: drag)))
        .contentShape(Rectangle())
        .overlay(alignment: .topLeading) {
            Button { close() } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.25), in: Circle())
            }
            .accessibilityLabel("Close player")
            .accessibilityIdentifier("closeNowPlaying")
            .padding(8)
        }
        .overlay(alignment: .bottom) { toast }
        .animation(.easeInOut(duration: 0.2), value: actions.message)
        .preferredColorScheme(.dark)
        .routerSheets(active: true)
        .sheet(isPresented: $showsQueue) { QueueSheet() }
        .sheet(item: $artworkTarget) { ArtworkPickerSheet(target: $0) }
        .sheet(isPresented: $showsMarks) { MarksSheet() }
        .sheet(isPresented: $showsAudioDetails) { AudioDetailsView() }
        .fullScreenCover(isPresented: $showsVisualizer) { VisualizerView() }
        .fullScreenCover(isPresented: $showsLyrics) { ExpandedLyrics(previous: previous, next: next) }
        .sheet(isPresented: $showsEqualizer) {
            NavigationStack {
                EqualizerView().toolbar { Button("Done") { showsEqualizer = false } }
            }
        }
    }

    /// Pull the artwork down to close the player.
    private var pullGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .updating($headerPullActive) { _, active, _ in active = true }
            .onChanged { pulled($0.translation.height) }
            .onEnded { pullEnded($0.translation.height, $0.predictedEndTranslation.height) }
    }

    private func pulled(_ distance: CGFloat) { drag.update(distance) }

    private func pullEnded(_ distance: CGFloat, _ predicted: CGFloat) {
        if distance > 140 || predicted > 420 {
            close(velocity: (predicted - distance) * 4)
        } else {
            drag.restore(reduceMotion: reduceMotion)
        }
    }

    private func close(velocity: CGFloat? = nil) {
        drag.beginDismissal(reduceMotion: reduceMotion, velocity: velocity)
        router.showsNowPlaying = false
    }

    private func previousEntry(_ state: PlaybackState) -> QueueEntry? {
        PlayOrder.previous(before: state.currentIndex, count: state.queue.count, repeatMode: state.repeatMode).map { state.queue[$0] }
    }

    /// Previous restarts the song after a few seconds.
    private func previous() {
        if player.currentPositionMs() > 3_000 || previousEntry(player.state) == nil {
            player.skipPrevious()
        } else {
            player.skipToPreviousItem()
        }
    }

    private func next() { player.skipNext() }

    @ViewBuilder
    private var toast: some View {
        if let message = actions.message {
            LibraryActionToast(text: message, id: actions.messageID)
                .padding(.bottom, Spacing.xl)
        }
    }

    private var menu: some View {
        let song = player.state.currentSong
        let hidden = song.map { mixes.hidden.contains($0.id) } ?? false
        return Menu {
            Section("Track") {
                Button { router.songForDetails = song } label: { Label("Music information", systemImage: "info.circle") }
                Button { showsAudioDetails = true } label: { Label("Audio details", systemImage: "waveform.badge.magnifyingglass") }
                if let album = song.flatMap({ library.album($0.albumId) }) {
                    Button { artworkTarget = .album(album) } label: { Label("Find a better cover", systemImage: "photo.badge.magnifyingglass") }
                }
            }
            Section("Library") {
                Button { addBookmark() } label: { Label("Bookmark this moment", systemImage: "bookmark") }
                Button { showsMarks = true } label: {
                    Label(player.state.abLoop?.enabled == true ? "Bookmarks & A–B loop (on)" : "Bookmarks & A–B loop", systemImage: "bookmark.square")
                }
                Button { if let song { router.songsForPlaylist = [song] } } label: { Label("Add to playlist", systemImage: "text.badge.plus") }
                if let song {
                    Button { mixes.setHidden(song.id, !hidden) } label: {
                        Label(hidden ? "Show in Smart Playlists again" : "Hide from Smart Playlists", systemImage: hidden ? "eye" : "eye.slash")
                    }
                }
            }
            Section("Playback") {
                Button { showsLyrics = true } label: { Label("Lyrics", systemImage: "quote.bubble") }
                Button { close() } label: { Label("Close player", systemImage: "chevron.down") }
                if vybeEnabled, let song {
                    Button { router.showsNowPlaying = false; router.open(.radio(.song(song.id))) } label: { Label("Browse radio", systemImage: "dot.radiowaves.left.and.right") }
                }
                if vybeEnabled, let radio = actions.radio, let song, radio.startSongId == song.id || radio.suggested.contains(song.id) {
                    Button { actions.refreshRadio() } label: { Label("New radio picks", systemImage: "arrow.clockwise") }
                }
                Button { showsQueue = true } label: { Label("Queue", systemImage: "music.note.list") }
                Button { showsVisualizer = true } label: { Label("Visualizer", systemImage: "waveform") }
                Button { showsEqualizer = true } label: { Label("Equalizer", systemImage: "slider.vertical.3") }
            }
        } label: {
            Image(systemName: "line.3.horizontal").font(.title3.weight(.semibold))
                .frame(width: 48, height: 48).contentShape(Rectangle())
        }
        .menuStyle(.button)
        .disabled(song == nil)
        .accessibilityLabel("More options")
    }

    private func addBookmark() {
        guard let song = player.state.currentSong else { return }
        let position = player.currentPositionMs()
        do {
            _ = try AppServices.shared.database.addBookmark(songId: song.id, positionMs: position)
            actions.show("Bookmarked \(formatDuration(position))")
        } catch {
            actions.show("Couldn't save the bookmark: \(error.localizedDescription)")
        }
    }

    private func referenceOptions(_ song: Song, state: PlaybackState) -> some View {
        HStack {
            Button { actions.toggleFavorite(song) } label: {
                Image(systemName: song.isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 25, weight: .bold))
                    .frame(width: 48, height: 48)
            }
            .accessibilityLabel(song.isFavorite ? "Remove from favorites" : "Add to favorites")
            Spacer()
            Button { showsAudioDetails = true } label: {
                VStack(spacing: 1) {
                    Image(systemName: "hifispeaker.fill")
                    Text(song.sampleRate > 0 ? MediaFormats.sampleRateText(song.sampleRate) : "Audio")
                }.font(.system(size: 10, weight: .bold)).frame(minWidth: 48, minHeight: 48)
            }
            .accessibilityLabel("Audio details")
            Spacer(minLength: 60)
            ToggleIcon(systemImage: "shuffle", active: state.shuffleModeEnabled) {
                player.setShuffleModeEnabled(!state.shuffleModeEnabled)
            }.accessibilityLabel("Shuffle")
            Spacer()
            ToggleIcon(systemImage: state.repeatMode == .one ? "repeat.1" : "repeat", active: state.repeatMode != .off) {
                player.cycleRepeatMode()
            }.accessibilityLabel("Repeat")
        }
    }

    private func controls(_ state: PlaybackState) -> some View {
        HStack(spacing: 3) {
            transport("backward.end.fill", label: "Previous track", size: 50, action: { player.skipToPreviousItem() })
            transport("backward.fill", label: "Rewind 10 seconds", size: 68, action: { player.seek(to: max(0, player.currentPositionMs() - 10_000)) })
            transport(state.isPlaying ? "pause.fill" : "play.fill", label: state.isPlaying ? "Pause" : "Play", size: 84, action: { player.togglePlayPause() })
            transport("forward.fill", label: "Forward 10 seconds", size: 68, action: { player.seek(to: min(state.durationMs, player.currentPositionMs() + 10_000)) })
            transport("forward.end.fill", label: "Next track", size: 50, action: next)
        }
    }

    private func transport(_ symbol: String, label: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.43, weight: .black))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(.black, in: Circle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.92))
        .accessibilityLabel(label)
        .accessibilityIdentifier(symbol == "play.fill" || symbol == "pause.fill" ? "nowPlayingPlayPause" : label)
    }

    private var referenceNavigation: some View {
        HStack {
            Button { close(); router.select(.library) } label: { Image(systemName: "square.grid.2x2.fill") }
                .accessibilityLabel("Library")
            Spacer()
            Button { showsEqualizer = true } label: { Image(systemName: "chart.bar.fill") }
                .accessibilityLabel("Equalizer")
            Spacer()
            Button { close(); router.showsSearch = true } label: { Image(systemName: "magnifyingglass") }
                .accessibilityLabel("Search")
            Spacer()
            menu
        }
        .font(.system(size: 28, weight: .heavy))
        .foregroundStyle(.white.opacity(0.6))
        .frame(height: 48)
        .padding(.horizontal, 42)
    }

    private func audioSummary(_ song: Song) -> String {
        [song.sampleRate > 0 ? MediaFormats.sampleRateText(song.sampleRate) : nil,
         song.bitrate > 0 ? MediaFormats.bitrateText(song.bitrate) : nil,
         song.url.pathExtension.uppercased()].compactMap { $0 }.joined(separator: "  ").uppercased()
    }

    private func backdrop(_ song: Song?) -> some View {
        ReferencePlayerBackdrop(song: song)
    }

}

/// A toggle in the controls (shuffle, repeat): its icon dimmed when off, on a soft disc when on.
private struct ToggleIcon: View {
    let systemImage: String
    let active: Bool
    let action: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage).font(.title3.weight(.semibold))
                .foregroundStyle(active ? palette.primary : palette.onSurface.opacity(0.6))
                .frame(width: 48, height: 48)
                .background(Circle().fill(palette.primary.opacity(active ? 0.18 : 0)))
                .contentShape(Circle())
        }
        .animation(.easeInOut(duration: 0.2), value: active)
    }
}

/// Real track waveform with transport controls overlaid and elapsed/duration badges.
private struct ProgressSection<Controls: View>: View {
    let song: Song
    @ViewBuilder let controls: () -> Controls
    @Environment(PlayerController.self) private var player
    @State private var previewMs: Int64?
    @State private var levels: [Float]?
    @State private var bookmarks: [Int64] = []

    var body: some View {
        let state = player.state
        let duration = max(state.durationMs > 0 ? state.durationMs : song.durationMs, 1)
        GeometryReader { geometry in
            ZStack {
                WaveformSeekBar(levels: levels, positionMs: player.clock.positionMs,
                                durationMs: duration, bookmarks: bookmarks,
                                loop: state.abLoop?.songId == song.id ? state.abLoop : nil,
                                previewMs: $previewMs, onSeek: { player.seek(to: $0) },
                                referenceStyle: true, barHeight: geometry.size.height)
                controls()
            }
            .overlay(alignment: .bottom) {
                HStack {
                    timeBadge(previewMs ?? player.clock.positionMs)
                    Spacer()
                    timeBadge(duration)
                }
                .allowsHitTesting(false)
            }
        }
        .task(id: song.id) {
            levels = nil
            previewMs = nil
            bookmarks = ((try? AppServices.shared.database.bookmarks(songId: song.id)) ?? []).map(\.positionMs)
            let result = await AppServices.shared.waveforms.waveform(song)
            guard !Task.isCancelled else { return }
            if case .ready(let loaded) = result { levels = loaded }
        }
    }

    private func timeBadge(_ ms: Int64) -> some View {
        Text(formatDuration(ms))
            .font(.system(size: 14, weight: .bold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(.black, in: Capsule())
    }
}

private struct ReferencePlayerBackdrop: View {
    let song: Song?
    @State private var artworkPalette = ArtworkPaletteState()

    var body: some View {
        let colors = LyricsColors(artworkPalette.palette(for: song?.url), scheme: .dark)
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                LinearGradient(colors: colors.gradient, startPoint: .top, endPoint: .bottom)
                if let song {
                    SongArtworkView(song: song, maxPixels: 1600)
                        .frame(width: geometry.size.width, height: geometry.size.height * 0.65)
                        .clipped()
                        .mask {
                            LinearGradient(stops: [.init(color: .white, location: 0),
                                                   .init(color: .white, location: 0.65),
                                                   .init(color: .clear, location: 1)],
                                           startPoint: .top, endPoint: .bottom)
                        }
                }
                LinearGradient(colors: [.clear, .black.opacity(0.15), .black.opacity(0.78)],
                               startPoint: .top, endPoint: .bottom)
            }
        }
        .task(id: song?.url) {
            guard let url = song?.url else { return }
            let revision = ArtworkLoader.shared.revision(for: url.path)
            let sampled = await LyricsPaletteCache.shared.palette(for: url)
            guard !Task.isCancelled else { return }
            artworkPalette.set(sampled, for: url, revision: revision)
        }
    }
}

/// The full lyrics over Now Playing (Android's ExpandedLyrics): the song at the top, the lyrics in
/// the artwork's colours on its gradient, previous / play / next underneath.
private struct ExpandedLyrics: View {
    let previous: () -> Void
    let next: () -> Void
    @Environment(PlayerController.self) private var player
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var artworkPalette = ArtworkPaletteState()

    var body: some View {
        let state = player.state
        let colors = LyricsColors(artworkPalette.palette(for: state.currentSong?.url), scheme: scheme)
        VStack(spacing: 0) {
            HStack(spacing: Spacing.xs) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.down").font(.title3.weight(.semibold)).frame(width: 48, height: 48).contentShape(Rectangle())
                }
                .accessibilityLabel("Close lyrics")
                VStack(alignment: .leading, spacing: 0) {
                    Text(state.currentSong?.title ?? "").font(.headline).foregroundStyle(colors.content).lineLimit(1)
                    Text(state.currentSong?.artist ?? "").font(.caption).foregroundStyle(colors.secondary).lineLimit(1)
                }
                Spacer()
            }
            .foregroundStyle(colors.content)
            .padding(.leading, Spacing.xs)
            .padding(.trailing, Spacing.lg)
            .padding(.top, Spacing.sm)
            if let song = state.currentSong {
                LyricsPanel(song: song).frame(maxHeight: .infinity)
            } else {
                Spacer()
            }
            HStack {
                Button(action: previous) { Image(systemName: "backward.end.fill").font(.system(size: 28)).frame(width: 56, height: 56).contentShape(Rectangle()) }
                    .accessibilityLabel("Previous")
                    .frame(maxWidth: .infinity)
                Button { player.togglePlayPause() } label: {
                    Image(systemName: state.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 30)).contentTransition(.symbolEffect(.replace))
                        .frame(width: 56, height: 56).contentShape(Rectangle())
                }
                .accessibilityLabel(state.isPlaying ? "Pause" : "Play")
                .frame(maxWidth: .infinity)
                Button(action: next) { Image(systemName: "forward.end.fill").font(.system(size: 28)).frame(width: 56, height: 56).contentShape(Rectangle()) }
                    .accessibilityLabel("Next")
                    .frame(maxWidth: .infinity)
            }
            .foregroundStyle(colors.content)
            .padding(.vertical, Spacing.sm)
        }
        .buttonStyle(.plain)
        .background(LinearGradient(colors: colors.gradient, startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        .task(id: state.currentSong?.url) {
            guard let url = state.currentSong?.url else { return }
            let revision = ArtworkLoader.shared.revision(for: url.path)
            let next = await LyricsPaletteCache.shared.palette(for: url)
            guard !Task.isCancelled else { return }
            artworkPalette.set(next, for: url, revision: revision)
        }
    }
}

/// The queue and what has played this session: reorder, remove (with undo), shuffle upcoming,
/// save as a playlist, play a history entry again.
struct QueueSheet: View {
    @Environment(PlayerController.self) private var player
    @Environment(LibraryActions.self) private var actions
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0
    @State private var savingName = ""
    @State private var saving = false
    @State private var feedback: String?
    @State private var feedbackID = UUID()

    var body: some View {
        let state = player.state
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Page", selection: $page) {
                    Text("Queue (\(state.queue.count))").tag(0)
                    Text("History").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Spacing.gutter)
                .padding(.vertical, Spacing.sm)
                if page == 0 { queue(state) } else { history(state) }
            }
            .navigationTitle(page == 0 ? "Queue" : "History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                if page == 0 {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Button { if !player.shuffleUpcoming() { showFeedback("Fewer than two songs are coming up") } } label: {
                                Label("Shuffle upcoming", systemImage: "shuffle")
                            }
                            Button { saving = true } label: { Label("Save as playlist", systemImage: "square.and.arrow.down") }
                            Button { showFeedback(player.undoQueueRemoval() ? "Removal undone" : "Nothing to undo") } label: {
                                Label("Undo removal", systemImage: "arrow.uturn.backward")
                            }
                        } label: { Image(systemName: "ellipsis.circle") }
                    }
                }
            }
            .alert("Save queue as playlist", isPresented: $saving) {
                TextField("Name", text: $savingName)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    actions.createPlaylist(savingName, songs: player.state.queue.map(\.song))
                    savingName = ""
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let feedback { Toast(text: feedback).padding(.horizontal, Spacing.gutter).padding(.bottom, Spacing.md).allowsHitTesting(false) }
        }
        .task(id: feedbackID) {
            guard feedback != nil else { return }
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            guard !Task.isCancelled else { return }
            feedback = nil
        }
        .presentationDetents([.medium, .large])
    }

    private func showFeedback(_ text: String) { feedback = text; feedbackID = UUID() }

    private func queue(_ state: PlaybackState) -> some View {
        List {
            if state.queue.isEmpty {
                Text("No track playing").foregroundStyle(palette.onSurfaceVariant)
            }
            ForEach(Array(state.queue.enumerated()), id: \.element.id) { index, entry in
                Button { player.skipToQueueItem(index) } label: {
                    row(entry.song, highlighted: index == state.currentIndex)
                }
                .buttonStyle(.plain)
                .opacity(index < state.currentIndex ? 0.55 : 1)
            }
            .onDelete { offsets in offsets.sorted(by: >).forEach { player.removeFromQueue($0) } }
            .onMove { source, destination in
                guard let from = source.first else { return }
                player.reorder(from: from, to: destination > from ? destination - 1 : destination)
            }
        }
        .listStyle(.plain)
        .environment(\.editMode, .constant(.active))
    }

    private func history(_ state: PlaybackState) -> some View {
        List {
            if state.history.isEmpty {
                Text("Songs you play this session show up here.").foregroundStyle(palette.onSurfaceVariant)
            }
            ForEach(state.history) { entry in
                HStack {
                    row(entry.song, highlighted: false)
                    Button { player.playFromHistory(entry.entryId) } label: { Image(systemName: "arrow.counterclockwise").frame(width: 44, height: 44) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Play \(entry.song.title) again")
                }
            }
        }
        .listStyle(.plain)
    }

    private func row(_ song: Song, highlighted: Bool) -> some View {
        HStack(spacing: Spacing.md) {
            SongArtworkView(song: song, maxPixels: 132)
                .frame(width: ArtworkSize.compact, height: ArtworkSize.compact)
                .clipShape(RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(song.title).font(.subheadline.weight(.semibold)).foregroundStyle(highlighted ? Color.accentColor : palette.onSurface).lineLimit(1)
                Text(song.artist).font(.caption).foregroundStyle(palette.onSurfaceVariant).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

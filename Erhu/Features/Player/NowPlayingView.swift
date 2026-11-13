import SwiftUI
import AVFoundation

/// Full-bleed artwork player with waveform transport and compact library navigation.
struct NowPlayingView: View {
    @Environment(\.vybeEnabled) private var vybeEnabled
    @Environment(PlayerController.self) private var player
    @Environment(LibraryActions.self) private var actions
    @Environment(AppRouter.self) private var router
    @Environment(LibraryStore.self) private var library
    @Environment(\.palette) private var palette
    @Environment(\.playerReduceMotion) private var reduceMotion
    @State private var artworkDrag = 0.0
    @State private var artworkGestureMode = 0
    @State private var artworkGestureEntry: UUID?
    @State private var artworkTarget: ArtworkTarget?
    let drag: PlayerDragState
    @State private var showsQueue = false
    @State private var showsLyrics = false
    @State private var showsMarks = false
    @State private var showsVisualizer = false
    @State private var showsEqualizer = false
    @State private var showsAudioDetails = false
    @GestureState private var artworkGestureActive = false

    var body: some View {
        let state = player.state
        GeometryReader { geometry in
            if let current = state.currentSong {
                let song = library.songs.first(where: { $0.id == current.id }) ?? current
                let width = geometry.size.width
                let height = geometry.size.height
                ZStack {
                    Color.clear.contentShape(Rectangle())
                        .accessibilityAction(named: "Close player") { close() }
                    artworkInteraction(width: width)
                        .frame(width: width, height: height * 0.55)
                        .position(x: width / 2, y: height * 0.275)
                    Button { reveal(song, album: false) } label: {
                        Text(song.title)
                        .font(.custom(PlayerButtonConstants.titleFont, size: PlayerButtonConstants.titleSize))
                        .lineLimit(1).minimumScaleFactor(0.75)
                    }
                        .accessibilityIdentifier("nowPlayingTitle")
                        .frame(width: width - 32).position(x: width / 2, y: height * 0.60)
                    Button { reveal(song, album: true) } label: {
                        Text(song.artist + PlayerButtonConstants.metadataSeparator + song.album)
                        .font(.custom(PlayerButtonConstants.subtitleFont, size: PlayerButtonConstants.subtitleSize))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.center)
                    }
                        .accessibilityIdentifier("nowPlayingAlbum")
                        .frame(width: width - 32).position(x: width / 2, y: height * 0.633)
                    referenceOptions(song, state: state, width: width)
                        .frame(width: width, height: 48).position(x: width / 2, y: height * 0.675)
                    ProgressSection(song: song) { controls(state, width: width) }
                        .frame(width: width - 20, height: height * 0.18)
                        .position(x: width / 2, y: height * 0.79)
                    Button { showsAudioDetails = true } label: {
                        Text(audioSummary(song)).font(.custom("AvenirNext-Bold", size: 10.5))
                            .lineLimit(1).minimumScaleFactor(0.75)
                    }
                    .frame(width: width - 24).position(x: width / 2, y: height * 0.895)
                    referenceNavigation.frame(width: width, height: 44)
                        .position(x: width / 2, y: height * 0.94)
                }
                .foregroundStyle(.white)
            } else {
                EmptyState(message: "Nothing is playing. Pick a song from your library.", systemImage: "music.note")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .ignoresSafeArea()
        .persistentSystemOverlays(.visible)
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(PlayerForegroundMotion(drag: drag))
        .modifier(PlayerChromeOpacity(progress: drag.progress))
        .onChange(of: artworkGestureActive) { _, active in
            guard !active else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(16))
                guard !artworkGestureActive, artworkGestureMode != 0 else { return }
                artworkGestureMode = 0
                artworkGestureEntry = nil
                restoreArtworkDrag()
                drag.cancelGesture(reduceMotion: reduceMotion)
            }
        }
        .onChange(of: drag.isMoving, initial: true) { _, active in player.setVisualMotion(.presentation, active: active) }
        .onDisappear {
            player.setVisualMotion(.presentation, active: false)
            player.setVisualMotion(.carousel, active: false)
        }
        .background(backdrop(state.currentSong).ignoresSafeArea().modifier(PlayerBackdropFade(drag: drag)))
        .contentShape(Rectangle())
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

    private func artworkInteraction(width: CGFloat) -> some View {
        Rectangle().fill(Color.white.opacity(0.001))
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 10, coordinateSpace: .local)
            .updating($artworkGestureActive) { _, active, _ in active = true }
            .onChanged { sample in
                if artworkGestureMode == 0 {
                    if HorizontalGestureIntent.accepts(sample.translation) { artworkGestureMode = 1 }
                    else if sample.translation.height > abs(sample.translation.width) { artworkGestureMode = 2 }
                    else { return }
                    artworkGestureEntry = player.state.currentEntry?.id
                }
                guard artworkGestureEntry == player.state.currentEntry?.id else { return }
                if artworkGestureMode == 1 {
                    let direction = sample.translation.width < 0 ? 1 : -1
                    let available = canSwipeArtwork(direction)
                    artworkDrag = Double(sample.translation.width / max(width, 1)).clamped(-0.95, 0.95) * (available ? 1 : 0.12)
                } else { pulled(sample.translation.height) }
            }
            .onEnded { sample in
                defer { artworkGestureMode = 0; artworkGestureEntry = nil }
                guard artworkGestureEntry == player.state.currentEntry?.id else { restoreArtworkDrag(); return }
                if artworkGestureMode == 1 {
                    let velocity = (sample.predictedEndTranslation.width - sample.translation.width) * 5
                    let direction = ArtworkSwipeIntent.direction(translation: Double(sample.translation.width),
                        velocity: Double(velocity), width: Double(width),
                        canNext: canSwipeArtwork(1), canPrevious: canSwipeArtwork(-1))
                    if direction > 0 { player.skipNext() }
                    else if direction < 0 { player.skipToPreviousItem() }
                    else { restoreArtworkDrag() }
                } else if artworkGestureMode == 2 {
                    pullEnded(sample.translation.height, sample.predictedEndTranslation.height)
                } else { restoreArtworkDrag() }
            })
        .accessibilityElement()
        .accessibilityLabel("Album artwork")
        .accessibilityIdentifier("nowPlayingArtwork")
        .accessibilityAction(named: "Next track") { player.skipNext() }
        .accessibilityAction(named: "Previous track") { player.skipToPreviousItem() }
    }

    private func canSwipeArtwork(_ direction: Int) -> Bool {
        let state = player.state
        let index = direction > 0
            ? PlayOrder.next(after: state.currentIndex, count: state.queue.count, repeatMode: state.repeatMode, userSkip: true)
            : PlayOrder.previous(before: state.currentIndex, count: state.queue.count, repeatMode: state.repeatMode)
        guard let index, state.queue.indices.contains(index) else { return false }
        return state.queue[index].id != state.currentEntry?.id
    }

    private func restoreArtworkDrag() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.28)) { artworkDrag = 0 }
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

    private func reveal(_ song: Song, album: Bool) {
        close()
        if !router.revealSong(song, album: album, source: player.state.currentEntry?.source, library: library) {
            actions.show(PlayerButtonConstants.locationUnavailable)
        }
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

            }
            Section("Playback") {
                Button { showsLyrics = true } label: { Label("Lyrics", systemImage: "quote.bubble") }
                Button { close() } label: { Label("Close player", systemImage: "chevron.down") }
                    .accessibilityIdentifier("closeNowPlaying")
                if vybeEnabled, let song {
                    Button { router.showsNowPlaying = false; router.open(.radio(.song(song.id))) } label: { Label("Browse radio", systemImage: "dot.radiowaves.left.and.right") }
                }
                if vybeEnabled, let radio = actions.radio, let song, radio.startSongId == song.id || radio.suggested.contains(song.id) {
                    Button { actions.refreshRadio() } label: { Label("New radio picks", systemImage: "arrow.clockwise") }
                }
                Button { showsQueue = true } label: { Label("Queue", systemImage: "music.note.list") }
                Button { showsVisualizer = true } label: { Label("Visualizer", systemImage: "waveform") }
                Button { showsEqualizer = true } label: { Label("Equalizer", systemImage: "slider.vertical.3") }
                Button {
                    close()
                    router.open(.settingsPage(.playback))
                } label: { Label("Playback settings", systemImage: "waveform") }
            }
        } label: {
            Image(systemName: PlayerButtonConstants.optionsSymbol)
                .rotationEffect(.degrees(PlayerButtonConstants.optionsRotation))
                .font(.system(size: PlayerButtonConstants.iconSize, weight: .black))
                .foregroundStyle(.white.opacity(PlayerButtonConstants.iconOpacity))
                .frame(width: PlayerButtonConstants.touchSize, height: PlayerButtonConstants.touchSize)
                .contentShape(Rectangle())
        }.accessibilityIdentifier("nowPlayingMenu")
        .menuStyle(.button)
        .disabled(song == nil)
        .accessibilityLabel(PlayerButtonConstants.optionsLabel)
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

    private func referenceOptions(_ song: Song, state: PlaybackState, width: CGFloat) -> some View {
        ZStack {
            Button { actions.toggleFavorite(song) } label: {
                Image(systemName: song.isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 25, weight: .bold)).frame(width: 44, height: 44)
            }
            .accessibilityLabel(song.isFavorite ? "Remove from favorites" : "Add to favorites")
            .position(x: width * 0.12, y: 24)
            PlayerShareButton(song: song)
                .position(x: width * 0.31, y: 24)
            menu.position(x: width * PlayerButtonConstants.centerFraction, y: 24)
            ToggleIcon(systemImage: "shuffle", active: state.shuffleModeEnabled) {
                player.setShuffleModeEnabled(!state.shuffleModeEnabled)
            }.accessibilityLabel("Shuffle").position(x: width * 0.69, y: 24)
            ToggleIcon(systemImage: state.repeatMode == .one ? "repeat.1" : "repeat", active: state.repeatMode != .off) {
                player.cycleRepeatMode()
            }.accessibilityLabel("Repeat").position(x: width * 0.88, y: 24)
        }
    }

    private func controls(_ state: PlaybackState, width: CGFloat) -> some View {
        let playIntent = state.isPlaying || state.status == .buffering
        return HStack(spacing: 3) {
            transport("seek.backward", identifier: "nowPlayingRewind", label: "Rewind 10 seconds", size: width * PlaybackPreferences.seekSize, action: { player.seek(to: max(0, player.currentPositionMs() - 10_000)) })
            transport("backward.fill", identifier: "nowPlayingPreviousTrack", label: "Previous track", size: width * PlaybackPreferences.skipSize, action: { player.skipToPreviousItem() })
            transport(playIntent ? "pause.fill" : "play.fill", identifier: "nowPlayingPlayPause", label: playIntent ? "Pause" : "Play", size: width * (playIntent ? PlaybackPreferences.playingSize : PlaybackPreferences.playSize), action: { player.togglePlayPause() })
            transport("forward.fill", identifier: "nowPlayingNextTrack", label: "Next track", size: width * PlaybackPreferences.skipSize, action: next)
            transport("seek.forward", identifier: "nowPlayingForward", label: "Forward 10 seconds", size: width * PlaybackPreferences.seekSize, action: { player.seek(to: min(state.durationMs, player.currentPositionMs() + 10_000)) })
        }
        .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.75), value: playIntent)
    }

    private func transport(_ symbol: String, identifier: String, label: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if symbol.hasPrefix("seek.") {
                    HStack(spacing: -2) {
                        ForEach(0..<3) { _ in
                            Image(systemName: symbol == "seek.backward" ? "arrowtriangle.left.fill" : "arrowtriangle.right.fill")
                                .font(.system(size: size * 0.25, weight: .black))
                        }
                    }
                } else {
                    Image(systemName: symbol)
                        .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                        .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.8), value: symbol)
                }
            }
                .font(.system(size: size * 0.43, weight: .black))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(.black, in: Circle())
                .frame(minWidth: symbol.hasPrefix("seek.") ? PlayerButtonConstants.seekTouchSize : PlayerButtonConstants.touchSize,
                       minHeight: PlayerButtonConstants.touchSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlayerTransportPressStyle(reduceMotion: reduceMotion))
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    private var referenceNavigation: some View {
        HStack {
            Button { close(); router.select(.library) } label: { Image(systemName: "square.grid.2x2.fill") }
                .accessibilityLabel("Library")
            Spacer()
            Button { showsEqualizer = true } label: { PlayerEqualizerGlyph() }
                .accessibilityLabel("Equalizer")
            Spacer()
            Button { close(); router.showsSearch = true } label: { Image(systemName: "magnifyingglass") }
                .accessibilityLabel("Search")
            Spacer()
            Button {
                close()
                router.open(Tool.settings)
            } label: {
                PlayerQueueGlyph().font(.title3.weight(.semibold))
                    .frame(width: PlayerButtonConstants.touchSize, height: PlayerButtonConstants.touchSize)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(PlayerButtonConstants.settingsLabel)
            .accessibilityIdentifier("nowPlayingSettings")
        }
        .font(.system(size: 28, weight: .heavy))
        .foregroundStyle(.white.opacity(0.6))
        .frame(height: 48)
        .padding(.horizontal, 36)
    }

    private func audioSummary(_ song: Song) -> String {
        [song.sampleRate > 0 ? MediaFormats.sampleRateText(song.sampleRate) : nil,
         song.bitrate > 0 ? MediaFormats.bitrateText(song.bitrate) : nil,
         song.url.pathExtension.uppercased()].compactMap { $0 }.joined(separator: "  ").uppercased()
    }

    private func backdrop(_ song: Song?) -> some View {
        ReferencePlayerBackdrop(song: song, artworkDrag: $artworkDrag)
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
            Image(systemName: systemImage).font(.system(size: 25, weight: .black))
                .foregroundStyle(.white.opacity(active ? 1 : 0.5))
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
    @Environment(\.playerReduceMotion) private var reduceMotion
    @Environment(\.playerInMotion) private var playerInMotion
    @AppStorage(PlaybackPreferences.waveformKey) private var waveformMode = PlaybackPreferences.defaultWaveform
    @State private var previewMs: Int64?
    @State private var levels: [Float]?
    @State private var levelsSongID: Int64?
    @State private var bookmarks: [Int64] = []

    var body: some View {
        let state = player.state
        let entryID = state.currentEntry?.id
        let duration = max(state.durationMs > 0 ? state.durationMs : song.durationMs, 1)
        GeometryReader { geometry in
            ZStack {
                TimelineView(.animation(minimumInterval: 1.0 / 30,
                                        paused: !state.isPlaying || previewMs != nil || playerInMotion)) { _ in
                    let position = player.currentPositionMs()
                    WaveformSeekBar(levels: levelsSongID == song.id ? levels : nil, positionMs: position,
                                    durationMs: duration, bookmarks: bookmarks,
                                    loop: state.abLoop?.songId == song.id ? state.abLoop : nil,
                                    previewMs: $previewMs, onSeek: { target in
                                        guard player.state.currentEntry?.id == entryID else { return }
                                        player.seek(to: target)
                                    }, referenceStyle: true, scrollsWithPlayback: waveformMode == PlayerWaveformMode.scrolling.rawValue,
                                    barHeight: geometry.size.height)
                        .id(entryID)
                        .transition(reduceMotion ? .opacity : .modifier(
                            active: WaveformArrival(amount: 0), identity: WaveformArrival(amount: 1)))
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: entryID)
                        .overlay(alignment: .bottom) {
                            HStack {
                                timeBadge(previewMs ?? position)
                                    .accessibilityIdentifier("nowPlayingElapsed")
                                Spacer()
                                timeBadge(duration)
                            }
                            .allowsHitTesting(false)
                        }
                }
                // Transport must react to scrub completion even when the waveform clock is paused.
                controls()
                    .opacity(previewMs == nil ? 1 : 0)
                    .allowsHitTesting(previewMs == nil)
                    .accessibilityHidden(previewMs != nil)
                    .animation(reduceMotion ? nil : .easeInOut(duration: previewMs == nil ? 0.22 : 0.18), value: previewMs != nil)
            }
        }
        .onChange(of: entryID) { _, _ in previewMs = nil }
        .onChange(of: waveformMode) { _, _ in previewMs = nil }
        .task(id: entryID) {
            levels = nil
            levelsSongID = nil
            previewMs = nil
            bookmarks = ((try? AppServices.shared.database.bookmarks(songId: song.id)) ?? []).map(\.positionMs)
            let result = await AppServices.shared.waveforms.waveform(song)
            guard !Task.isCancelled, player.state.currentEntry?.id == entryID else { return }
            if case .ready(let loaded) = result {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
                    levelsSongID = song.id
                    levels = loaded
                }
            }
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

private struct WaveformArrival: ViewModifier {
    let amount: CGFloat
    func body(content: Content) -> some View {
        content.scaleEffect(x: 1, y: 0.08 + amount * 0.92).opacity(Double(amount))
    }
}

/// The cover keeps its full composition in a width-sized slot. Its lower edge
/// dissolves into the original dominant colour, which fills all remaining space.
struct PlayerArtworkBackground<Artwork: View>: View {
    let dominant: Color
    var topInset: CGFloat = 0
    var horizontalInset: CGFloat = 0
    @ViewBuilder var artwork: () -> Artwork

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                dominant
                artwork()
                    .frame(width: max(geometry.size.width - horizontalInset * 2, 1),
                           height: max(geometry.size.width - horizontalInset * 2, 1))
                    .shadow(color: .black.opacity(topInset > 0 ? 0.20 : 0), radius: 10, y: 3)
                    .mask {
                        LinearGradient(stops: [.init(color: .white, location: 0),
                                               .init(color: .white, location: 0.72),
                                               .init(color: .clear, location: 1)],
                                       startPoint: .top, endPoint: .bottom)
                    }
                    .padding(.top, topInset)
                // Keep the artwork itself intact; add depth to the colour extension
                // beneath it, with some of its hue still present at the bottom.
                LinearGradient(stops: [.init(color: .clear, location: 0),
                                       .init(color: .clear, location: min(geometry.size.width / max(geometry.size.height, 1) * 0.72, 0.6)),
                                       .init(color: .black.opacity(0.25), location: 0.65),
                                       .init(color: .black.opacity(0.88), location: 1)],
                               startPoint: .top, endPoint: .bottom)
                if topInset > 0 {
                    // Keep white system status text readable even over a white cover.
                    LinearGradient(stops: [.init(color: .black.opacity(0.60), location: 0),
                                           .init(color: .black.opacity(0.60), location: 0.60),
                                           .init(color: .clear, location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: topInset + 30)
                }
            }
        }
        .allowsHitTesting(false)
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

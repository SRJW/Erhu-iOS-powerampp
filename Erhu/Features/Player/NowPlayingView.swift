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
                    Text(song.title)
                        .font(.custom("AvenirNext-Bold", size: 22))
                        .lineLimit(1).minimumScaleFactor(0.75)
                        .accessibilityIdentifier("nowPlayingTitle")
                        .frame(width: width - 32).position(x: width / 2, y: height * 0.60)
                    Text("\(song.artist) - \(song.album)")
                        .font(.custom("AvenirNext-DemiBold", size: 14))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.center)
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

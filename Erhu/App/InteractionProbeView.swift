#if DEBUG
import SwiftUI
import AVFoundation

/// Native automation exercises production controls without a music import or network request.
struct InteractionProbeView: View {
    let page: String
    @Environment(AppRouter.self) private var router
    @State private var query = ""
    @State private var showsSearch = false
    @State private var chrome = LibraryChromeState()

    var body: some View {
        @Bindable var router = router
        Group {
            if page == "player" || page == "player-reduced-motion" {
                PlayerInteractionProbe(reduceMotion: page == "player-reduced-motion")
            } else if page == "search" {
                Button("Open search") { router.showsSearch = true }
                    .accessibilityIdentifier("openSearchProbe")
                    .sheet(isPresented: $router.showsSearch) { SearchView() }
            } else if page == "browse" {
                NavigationStack {
                    LibraryBrowseScrollView(title: "Albums", query: $query, showsSearch: $showsSearch) {
                        Text("Sort by title").accessibilityIdentifier("sortProbe")
                    } content: {
                        LazyVStack { ForEach(0..<100) { Text("Album \($0)").frame(height: 60) } }
                    }
                }.environment(chrome).environment(\.artworkSection, router.section)
            } else if page == "tools" {
                NavigationStack {
                    ToolView(tool: .autoFixTags).tracksLibraryScrolling(usesUIKit: true)
                        .overlay(alignment: .bottom) {
                            Text(String(format: "%.2f", Double(chrome.fraction))).accessibilityIdentifier("chromeFraction")
                        }
                }.environment(chrome).environment(\.artworkSection, router.section)
            } else if page == "animated-covers" {
                #if ERHU_ANIMATED_ART
                NavigationStack { AnimatedArtworkView() }
                #endif
            } else {
                NavigationStack { TransitionStudioRow(collection: .album(42)) }
            }
        }
    }
}

/// Uses the real root, mini player, presentation and transport. A local silent track
/// removes imports, network access, artwork availability and audio fixtures as prerequisites.
private struct PlayerInteractionProbe: View {
    let reduceMotion: Bool
    @Environment(PlayerController.self) private var player
    @Environment(AppSettings.self) private var settings
    @Environment(AppRouter.self) private var router
    @State private var ready = false
    @State private var failure: String?

    var body: some View {
        Group {
            if ready { RootView() }
            else if let failure { Text(failure).accessibilityIdentifier("playerProbeFailure") }
            else { ProgressView() }
        }
        .environment(\.playerReduceMotion, reduceMotion)
        .task {
            guard !ready else { return }
            settings.introductionCompleted = true
            router.showsNowPlaying = false
            // The controller restores persisted playback asynchronously on launch.
            for _ in 0..<100 {
                if player.restoreFinished { break }
                try? await Task.sleep(for: .milliseconds(50))
            }
            guard player.restoreFinished else { failure = "Playback restore did not finish"; return }
            do {
                let name = "player-interaction-probe.wav"
                let url = LibraryPaths.musicFolder.appendingPathComponent(name)
                try FileManager.default.createDirectory(at: LibraryPaths.musicFolder, withIntermediateDirectories: true)
                let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
                let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100)!
                buffer.frameLength = buffer.frameCapacity
                for frame in 0..<Int(buffer.frameLength) { buffer.floatChannelData![0][frame] = 0 }
                // Close the file before playback so its duration header has been finalized.
                do {
                    let file = try AVAudioFile(forWriting: url, settings: format.settings)
                    for _ in 0..<120 { try file.write(from: buffer) }
                }
                let song = Song(id: -9001, title: "Player presentation regression", artist: "Local fixture",
                                album: "No artwork", durationMs: 120_000, path: name)
                let next = Song(id: -9002, title: "Second player track", artist: "Local fixture",
                                album: "No artwork", durationMs: 120_000, path: name)
                player.playSongs([song, next])
                ready = true
            } catch { failure = error.localizedDescription }
        }
    }
}
#endif

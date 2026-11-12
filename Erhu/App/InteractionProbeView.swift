#if DEBUG
import SwiftUI
import AVFoundation
import UIKit

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
            if page == "player" || page == "player-reduced-motion" || page == "player-artwork" {
                PlayerInteractionProbe(reduceMotion: page == "player-reduced-motion", withArtwork: page == "player-artwork")
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
    var withArtwork = false
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
                try FileManager.default.createDirectory(at: LibraryPaths.musicFolder, withIntermediateDirectories: true)
                let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
                let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100)!
                buffer.frameLength = buffer.frameCapacity
                for frame in 0..<Int(buffer.frameLength) { buffer.floatChannelData![0][frame] = 0 }
                var songs: [Song] = []
                for index in 0..<2 {
                    let name = withArtwork ? "player-cover-probe-\(index).m4a" : "player-interaction-probe.wav"
                    let url = LibraryPaths.musicFolder.appendingPathComponent(name)
                    if withArtwork || index == 0 {
                        let settings: [String: Any] = withArtwork
                            ? [AVFormatIDKey: kAudioFormatAppleLossless, AVSampleRateKey: 44_100.0,
                               AVNumberOfChannelsKey: 1, AVEncoderBitDepthHintKey: 16]
                            : format.settings
                        // Close the file before adding tags or starting playback.
                        do {
                            let file = try AVAudioFile(forWriting: url, settings: settings)
                            for _ in 0..<120 { try file.write(from: buffer) }
                        }
                        if withArtwork {
                            let image = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).image { context in
                                (index == 0 ? UIColor.red : UIColor.blue).setFill()
                                context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
                            }
                            var edit = TagWriteRequest(); edit.artwork = image.pngData()
                            try TagWriter.write(edit, to: url)
                            ArtworkLoader.shared.forget(path: url.path)
                            _ = await ArtworkLoader.shared.image(for: url, maxPixels: 1600)
                            _ = await LyricsPaletteCache.shared.palette(for: url)
                        }
                    }
                    songs.append(Song(id: Int64(-9001 - index),
                        title: index == 0 ? "Player presentation regression" : "Second player track",
                        artist: "Local fixture", album: withArtwork ? "Colour cover fixture" : "No artwork",
                        durationMs: 120_000, path: name))
                }
                player.playSongs(songs)
                ready = true
            } catch { failure = error.localizedDescription }
        }
    }
}
#endif

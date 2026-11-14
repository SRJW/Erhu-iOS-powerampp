import SwiftUI

/// Constants shared by the compact player's gestures and progress hit target.
enum MiniPlayerMetrics {
    static let rowHeight: CGFloat = 44
    static let progressHeight: CGFloat = 16
    static let swipeThreshold: CGFloat = 48
    static let dragDistance: CGFloat = 12
    static let maximumOffset: CGFloat = 36
    static let seekLabel = "Mini player progress"
    static let nextLabel = "Next track"
    static let previousLabel = "Previous track"
}

struct MiniPlayer: View {
    let song: Song
    let onOpen: () -> Void
    @Environment(PlayerController.self) private var player
    @Environment(AppRouter.self) private var router
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var translation = CGSize.zero

    var body: some View {
        let state = player.state
        let entry = state.currentEntry?.id
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Button(action: onOpen) {
                    HStack(spacing: Spacing.md) {
                        SongArtworkView(song: song, maxPixels: 132)
                            .frame(width: ArtworkSize.miniPlayer, height: ArtworkSize.miniPlayer)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
                            .playerArtworkFrame(expanded: false)
                            .modifier(MiniArtworkVisibility(enabled: router.presentedTool == nil))
                            .accessibilityLabel("Album artwork")
                        VStack(alignment: .leading, spacing: 1) {
                            Text(song.title).font(.subheadline.weight(.semibold)).foregroundStyle(palette.onSurface).lineLimit(1)
                            Text(song.subtitle).font(.caption).foregroundStyle(palette.onSurfaceVariant).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .offset(x: reduceMotion ? 0 : min(max(translation.width, -MiniPlayerMetrics.maximumOffset), MiniPlayerMetrics.maximumOffset))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open Now Playing")
                .accessibilityIdentifier("openNowPlaying")
                .accessibilityHint("Tap to open. Swipe left or right to change tracks; swipe up to open.")
                .accessibilityAction(named: MiniPlayerMetrics.nextLabel) { player.skipNext() }
                .accessibilityAction(named: MiniPlayerMetrics.previousLabel) { player.skipToPreviousItem() }
                .highPriorityGesture(DragGesture(minimumDistance: MiniPlayerMetrics.dragDistance)
                    .updating($translation) { value, state, _ in state = value.translation }
                    .onEnded { value in
                        guard player.state.currentEntry?.id == entry else { return }
                        let delta = value.translation
                        if abs(delta.width) > abs(delta.height) * 1.3, abs(delta.width) >= MiniPlayerMetrics.swipeThreshold {
                            if delta.width < 0 { player.skipNext() } else { player.skipToPreviousItem() }
                        } else if -delta.height >= MiniPlayerMetrics.swipeThreshold, abs(delta.height) > abs(delta.width) * 1.3 {
                            onOpen()
                        }
                    })
                Button { player.togglePlayPause() } label: {
                    Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2).frame(width: 44, height: MiniPlayerMetrics.rowHeight).contentShape(Rectangle())
                }
                .accessibilityLabel(state.isPlaying ? "Pause" : "Play")
                .accessibilityIdentifier("miniPlayerPlayPause")
            }
            .frame(height: MiniPlayerMetrics.rowHeight)
            MiniPlayerProgress(durationMs: state.durationMs, entryID: entry)
                .frame(height: MiniPlayerMetrics.progressHeight)
        }
        .foregroundStyle(palette.onSurface)
        .buttonStyle(.plain)
        .padding(.horizontal, Spacing.md)
        .contentShape(Rectangle())
    }
}

/// Seek has its own gesture region, separate from the song's horizontal swipe.
private struct MiniPlayerProgress: View {
    let durationMs: Int64
    let entryID: UUID?
    @Environment(PlayerController.self) private var player
    @Environment(\.palette) private var palette
    @State private var preview: Int64?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !player.state.isPlaying || preview != nil)) { _ in
            let position = preview ?? player.displayPositionMs()
            GeometryReader { geometry in
                let fraction = durationMs > 0 ? min(max(Double(position) / Double(durationMs), 0), 1) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.onSurfaceVariant.opacity(0.25)).frame(height: 3)
                    Capsule().fill(palette.primary).frame(width: geometry.size.width * fraction, height: 3)
                    if preview != nil {
                        Circle().fill(palette.primary).frame(width: 9, height: 9)
                            .offset(x: min(max(geometry.size.width * fraction - 4.5, 0), max(geometry.size.width - 9, 0)))
                    }
                }
                .frame(height: geometry.size.height)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard player.state.currentEntry?.id == entryID, durationMs > 0 else { return }
                        preview = FullTrackWaveformGeometry(durationMs: durationMs, width: geometry.size.width).position(at: value.location.x)
                    }
                    .onEnded { value in
                        defer { preview = nil }
                        guard player.state.currentEntry?.id == entryID, durationMs > 0 else { return }
                        player.seek(to: FullTrackWaveformGeometry(durationMs: durationMs, width: geometry.size.width).position(at: value.location.x))
                    })
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(MiniPlayerMetrics.seekLabel)
            .accessibilityIdentifier("miniPlayerProgress")
            .accessibilityValue("\(formatDuration(position)) of \(formatDuration(durationMs))")
            .accessibilityAdjustableAction { direction in
                let delta: Int64 = direction == .increment ? 10_000 : -10_000
                player.seek(to: min(max(player.currentPositionMs() + delta, 0), durationMs))
            }
        }
        .disabled(durationMs <= 0)
        .onChange(of: entryID) { _, _ in preview = nil }
        .onDisappear { preview = nil }
    }
}

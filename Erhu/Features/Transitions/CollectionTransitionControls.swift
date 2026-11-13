import SwiftUI

/// The ordinary collection song list, with direct access to each adjacent pair's editor.
struct CollectionTransitionTrackList: View {
    let collection: CollectionRef
    let tracks: [StudioTrack]
    var showTrackNumbers = false
    var songActions: SongActions? = nil
    @Environment(LibraryActions.self) private var actions
    @Environment(PlayerController.self) private var player
    @Environment(AppRouter.self) private var router
    @Environment(TransitionSettingsStore.self) private var transitions
    @State private var draft: EditorDraft?

    var body: some View {
        let songs = tracks.map(\.song)
        let slots = collection.kind == .playlist ? tracks.compactMap(\.occurrence.slot) : nil
        let pairs = collectionTransitionPairs(collection, tracks: tracks, config: transitions.config)
        let rowActions = songActions ?? router.songActions(actions, source: PlaybackSource(collection))
        LazyVStack(spacing: 0) {
            ForEach(Array(tracks.enumerated()), id: \.element.occurrence) { index, track in
                TrackRow(song: track.song, isCurrent: track.song.id == player.state.currentSong?.id,
                         showTrackNumber: showTrackNumbers, displayTrackNumber: showTrackNumbers ? index + 1 : nil,
                         actions: rowActions) {
                    actions.play(songs, startIndex: index, origin: collection, slots: slots)
                }
                .id(tracks.firstIndex(where: { $0.song.id == track.song.id }) == index
                    ? "amp-song-\(track.song.id)" : "amp-occurrence-\(index)")
                if pairs.indices.contains(index) {
                    CollectionTransitionConnector(pair: pairs[index]) {
                        draft = EditorDraft.open(.pair(pairs[index]), config: transitions.config)
                    }
                }
            }
        }
        .sheet(item: $draft) { _ in
            TransitionEditorView(draft: $draft, noun: collection.kind == .album ? "album" : "playlist")
        }
    }
}

private struct CollectionTransitionConnector: View {
    let pair: StudioPair
    let open: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            connectorLine
            Button(action: open) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "slider.horizontal.3")
                    Text(pairLabel(pair.choice))
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(palette.onSurface)
                .padding(.horizontal, Spacing.sm).padding(.vertical, 6)
                .background(palette.surfaceVariant.opacity(0.6), in: Capsule())
                .overlay(Capsule().stroke(palette.outline, lineWidth: 1))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit transition from \(pair.from.song.title) to \(pair.to.song.title): \(pairLabel(pair.choice))")
            .accessibilityHint("Opens preview and settings for this pair")
            connectorLine
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, Spacing.gutter + 16)
    }

    private var connectorLine: some View {
        Rectangle().fill(palette.outline).frame(width: 1, height: 6).padding(.leading, 12).accessibilityHidden(true)
    }
}

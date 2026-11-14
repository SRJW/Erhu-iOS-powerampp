import SwiftUI

struct SongRevealRequest: Hashable {
    let id = UUID()
    let songID: Int64
    let destination: Route
}

/// Wraps existing lists, rather than introducing a separate player destination screen.
struct PlayerSongReveal<Content: View>: View {
    let destination: Route
    let songs: [Song]
    var alphabetEnabled = false
    @ViewBuilder let content: Content
    @Environment(AppRouter.self) private var router

    private var readyRequest: SongRevealRequest? {
        guard let request = router.songReveal, request.destination == destination,
              songs.contains(where: { $0.id == request.songID }) else { return nil }
        return request
    }

    var body: some View {
        ScrollViewReader { proxy in
            content
                .padding(.trailing, alphabetEnabled ? 24 : 0)
                .overlay(alignment: .trailing) {
                    if alphabetEnabled {
                        SongAlphabetIndex(songs: songs) { id in proxy.scrollTo(Self.anchor(id), anchor: .top) }
                    }
                }
                .task(id: readyRequest) {
                guard let request = readyRequest else { return }
                defer {
                    if router.songReveal?.id == request.id {
                        router.highlightedSongID = nil
                        router.songReveal = nil
                    }
                }
                do {
                    // Let the destination and its asynchronously loaded rows finish layout.
                    try await Task.sleep(for: .seconds(PlayerButtonConstants.revealDelaySeconds))
                    proxy.scrollTo(Self.anchor(request.songID), anchor: .center)
                    router.highlightedSongID = request.songID
                    try await Task.sleep(for: .seconds(PlayerButtonConstants.highlightSeconds))
                } catch { /* Navigation cancels the transient highlight. */ }
            }
        }
    }

    static func anchor(_ songID: Int64) -> String { "amp-song-\(songID)" }
}

struct PlayerRevealedSong: ViewModifier {
    let songID: Int64
    @Environment(AppRouter.self) private var router
    func body(content: Content) -> some View {
        content.background {
            if router.highlightedSongID == songID {
                Color.accentColor.opacity(PlayerButtonConstants.highlightOpacity)
                    .allowsHitTesting(false)
            }
        }
    }
}

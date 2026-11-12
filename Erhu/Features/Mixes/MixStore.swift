import Foundation
import Observation

/// Builds radio selections on demand. Smart Playlists and their background rebuilds are removed.
@MainActor
@Observable
final class MixStore {
    private static let similarLimit = 500
    private let database: LibraryDatabase
    private let vybe: VybeEngine

    init(database: LibraryDatabase, vybe: VybeEngine) {
        self.database = database
        self.vybe = vybe
    }

    /// A radio from [seed]: built when asked, never in the background. [exclude]: earlier picks
    /// (when refreshing), which come back only if too few other songs are left.
    func radio(_ seed: RadioSeed, exclude: Set<Int64> = [], startSongId: Int64? = nil) async -> RadioPlan? {
        let database = database
        let vybe = vybe
        let hidden = Set<Int64>()
        let now = Self.now()
        guard let profile = await Task.detached(priority: .userInitiated, operation: {
            try? SmartMixEngine.profile(tracks: database.trackFacts(), plays: database.monthlyPlays(), now: now, hidden: hidden)
        }).value else { return nil }
        let anchors = RadioEngine.anchors(profile, seed)
        if anchors.isEmpty { return nil }
        // VYBE only refines the radio: no index means metadata and history alone.
        let seeds = Dictionary(anchors.map { ($0.songId, Float(1)) }, uniquingKeysWith: { a, _ in a })
        let similarity = await vybe.tasteNeighbours(seeds, limit: Self.similarLimit)
        return await Task.detached(priority: .userInitiated) {
            RadioEngine.build(profile, seed: seed, similarity: similarity, exclude: exclude, startSongId: startSongId)
        }.value
    }

    private static func now() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
}

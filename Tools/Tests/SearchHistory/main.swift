import Foundation

@main struct HistoryChecks {
    @MainActor static func main() {
        let suite = "amp-history-tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let history = SearchHistoryStore(defaults: defaults)
        var checks = 0
        func check(_ value: Bool, _ message: String) { precondition(value, message); checks += 1 }
        history.remember("  \n ", in: "songs")
        check(history.entries("songs").isEmpty, "Blank text is never a recent query")
        history.remember("Zoé", in: "songs")
        history.remember("Other", in: "songs")
        history.remember("  ZOE  ", in: "songs")
        check(history.entries("songs") == ["ZOE", "Other"], "Case and accent variants are deduplicated and moved to the front")
        history.remember("Muse", in: "library")
        check(history.entries("songs").count == 2, "Search surfaces keep independent histories")
        let restored = SearchHistoryStore(defaults: UserDefaults(suiteName: suite)!)
        check(restored.entries("songs") == ["ZOE", "Other"], "Recent queries persist across new stores")
        restored.remove("zoé", in: "songs")
        check(restored.entries("songs") == ["Other"], "Removing a term uses the same normalization")
        for i in 0..<20 { restored.remember("Query \(i)", in: "songs") }
        check(restored.entries("songs").count == SearchHistoryStore.limit, "History has a bounded size")
        check(restored.entries("songs").first == "Query 19" && restored.entries("songs").last == "Query 5", "Newest searches are retained in order")
        restored.clear("songs")
        let cleared = SearchHistoryStore(defaults: defaults)
        check(cleared.entries("songs").isEmpty, "Clear persists")
        check(cleared.entries("library") == ["Muse"], "Clear does not erase another surface's history")
        let now: Int64 = 1_800_000_000_000
        check(SongAddedPeriod.any.contains(0, now: now), "Any time includes unknown import dates")
        check(SongAddedPeriod.week.contains(now - 7 * 86_400_000, now: now), "The seven-day boundary is inclusive and uses milliseconds")
        check(!SongAddedPeriod.week.contains(now - 8 * 86_400_000, now: now), "Older songs are outside the seven-day filter")
        check(SongAddedPeriod.month.contains(now - 8 * 86_400_000, now: now), "The month filter includes the same older song")
        check(!SongAddedPeriod.month.contains(0, now: now) && !SongAddedPeriod.week.contains(now + 1, now: now), "Unknown and future dates cannot match a recent period")
        let batch = QueueDeletionPlan(songIDs: [1, 2, 3, 4, 5], currentIndex: 2, deletedIDs: [1, 3, 4])
        check(batch.retainedIndices == [1, 4] && batch.currentIndex == 1 && batch.currentWasDeleted, "A batch skips every deleted future file before continuing playback")
        let before = QueueDeletionPlan(songIDs: [1, 2, 3, 4], currentIndex: 2, deletedIDs: [1, 2])
        check(before.currentIndex == 0 && !before.currentWasDeleted, "Deleting earlier songs preserves the current entry")
        let last = QueueDeletionPlan(songIDs: [1, 2, 3, 4], currentIndex: 3, deletedIDs: [2, 4])
        check(last.retainedIndices == [0, 2] && last.currentIndex == 1, "Deleting the last song chooses the nearest surviving predecessor")
        let duplicates = QueueDeletionPlan(songIDs: [1, 2, 2, 3], currentIndex: 1, deletedIDs: [2])
        check(duplicates.retainedIndices == [0, 3] && duplicates.currentIndex == 1, "Every queue occurrence of a deleted file is removed")
        let empty = QueueDeletionPlan(songIDs: [1, 2], currentIndex: 0, deletedIDs: [1, 2])
        check(empty.retainedIndices.isEmpty && empty.currentIndex == -1, "Deleting the queue leaves no current song")
        print("Passed \(checks) persistent search-history, date-filter and batch queue checks")
    }
}

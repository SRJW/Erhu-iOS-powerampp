import Foundation

/// Remove every occurrence of deleted files, keeping the current entry or the next survivor.
struct QueueDeletionPlan {
    let retainedIndices: [Int]
    let currentIndex: Int
    let currentWasDeleted: Bool

    init(songIDs: [Int64], currentIndex oldIndex: Int, deletedIDs: Set<Int64>) {
        let kept = songIDs.indices.filter { !deletedIDs.contains(songIDs[$0]) }
        retainedIndices = kept
        currentWasDeleted = songIDs.indices.contains(oldIndex) && deletedIDs.contains(songIDs[oldIndex])
        if kept.isEmpty { currentIndex = -1 }
        else if let index = kept.firstIndex(of: oldIndex) { currentIndex = index }
        else if let index = kept.firstIndex(where: { $0 > oldIndex }) { currentIndex = index }
        else { currentIndex = kept.count - 1 }
    }
}

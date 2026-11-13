import Foundation

enum SongAddedPeriod: String, CaseIterable, Identifiable {
    case any, week, month
    var id: String { rawValue }
    var label: String {
        switch self { case .any: "Added"; case .week: "7 days"; case .month: "30 days" }
    }
    var description: String {
        switch self { case .any: "Any time"; case .week: "Last 7 days"; case .month: "Last 30 days" }
    }
    func contains(_ addedAt: Int64, now: Int64) -> Bool {
        guard self != .any else { return true }
        let days: Int64 = self == .week ? 7 : 30
        return addedAt > 0 && addedAt >= now - days * 86_400_000 && addedAt <= now
    }
}

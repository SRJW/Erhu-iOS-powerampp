import Foundation

struct PlayerWidgetSnapshot: Codable, Equatable {
    var title: String
    var artist: String
    var isPlaying: Bool
    var songID: Int64?
    var hasArtwork: Bool
    static let empty = Self(title: "Erhu", artist: "Open your music", isPlaying: false, songID: nil, hasArtwork: false)
    static let kind = "ErhuPlayerWidget"
    static var folder: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.erhu.player")
    }
    static func load() -> Self {
        guard let folder, let data = try? Data(contentsOf: folder.appendingPathComponent("player.json")),
              let value = try? JSONDecoder().decode(Self.self, from: data) else { return .empty }
        return value
    }
}

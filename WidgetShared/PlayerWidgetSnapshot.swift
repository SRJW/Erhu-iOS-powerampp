import Foundation

struct PlayerWidgetSnapshot: Codable, Equatable {
    var title: String
    var artist: String
    var isPlaying: Bool
    var songID: Int64?
    var hasArtwork: Bool
    var artworkFileName: String? = nil
    static let empty = Self(title: "amp", artist: "Open your music", isPlaying: false, songID: nil, hasArtwork: false)
    static let kind = "ErhuPlayerWidget"
    static var folder: URL? {
        PlayerWidgetStorage.shared?.folder
    }
    static func load() -> Self {
        guard let folder else {
            return Self(title: "Widget unavailable", artist: "Check widget status in amp Settings", isPlaying: false, songID: nil, hasArtwork: false)
        }
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("player.json")),
              let value = try? JSONDecoder().decode(Self.self, from: data) else { return .empty }
        return value
    }
}

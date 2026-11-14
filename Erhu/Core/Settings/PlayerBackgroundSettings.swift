import Foundation

/// Defaults reproduce the existing player; these affect appearance only.
struct PlayerBackgroundSettings: Codable, Equatable {
    var fadeStart = 0.75
    var blur = 24.0
    var details = 0.0
    var intensity = 1.0
    var saturation = 1.0
}

enum PlayerBackgroundControls {
    static let title = "Player artwork & background"
    static let fade = "Artwork fade"
    static let blur = "Background blur"
    static let details = "Background details"
    static let intensity = "Background intensity"
    static let saturation = "Background saturation"
    static let reset = "Restore background defaults"
    static let blurRange = 0.0...60.0
    static let unitRange = 0.0...1.0
    static let saturationRange = 0.0...2.0
}

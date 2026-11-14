import Foundation

/// Defaults reproduce the existing player; these affect appearance only.
struct PlayerBackgroundSettings: Codable, Equatable {
    var fadeStart = 0.75
    var blur = 24.0
    var details = 0.0
    var intensity = 1.0
    var saturation = 1.0
    var gradient = 0.0
    var gradientColor: UInt32 = 0xFF000000

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fadeStart = try c.decodeIfPresent(Double.self, forKey: .fadeStart) ?? 0.75
        blur = try c.decodeIfPresent(Double.self, forKey: .blur) ?? 24
        details = try c.decodeIfPresent(Double.self, forKey: .details) ?? 0
        intensity = try c.decodeIfPresent(Double.self, forKey: .intensity) ?? 1
        saturation = try c.decodeIfPresent(Double.self, forKey: .saturation) ?? 1
        gradient = try c.decodeIfPresent(Double.self, forKey: .gradient) ?? 0
        gradientColor = try c.decodeIfPresent(UInt32.self, forKey: .gradientColor) ?? 0xFF000000
    }
}

enum PlayerBackgroundControls {
    static let previewHeight = 180.0
    static let title = "Player artwork & background"
    static let gradient = "Background gradient"
    static let gradientColor = "Gradient colour"
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

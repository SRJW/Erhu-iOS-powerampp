import Foundation

enum PlayerWaveformMode: String, CaseIterable, Identifiable {
    case fullTrack, scrolling
    var id: String { rawValue }
    var label: String { self == .fullTrack ? "Static · full song" : "Scrolling · follows playback" }
}

enum PlaybackPreferences {
    static let waveformKey = "amp.player.waveformMode"
    static let defaultWaveform = PlayerWaveformMode.scrolling.rawValue
    static let crossfadeRange = 0.0...10.0
    static let crossfadeStep = 0.5
    static let seekSize: Double = 0.075
    static let skipSize: Double = 0.105
    static let playSize: Double = 0.15
    static let playingSize: Double = 0.12
    static let pressedScale = 0.85

    /// A manual handover must fit in the audio left on both decks.
    static func handoffDuration(requested: Int, outgoingRemaining: Int64, incomingRemaining: Int64) -> Int {
        max(1, min(max(requested, 20), Int(max(1, outgoingRemaining)), Int(max(1, incomingRemaining))))
    }
}

/// In static mode the same screen coordinate always represents the same time in the file.
struct FullTrackWaveformGeometry {
    let durationMs: Int64
    let width: Double
    func position(at x: Double) -> Int64 {
        guard width.isFinite, width > 0, x.isFinite, durationMs > 0 else { return 0 }
        return Int64((min(max(x / width, 0), 1) * Double(durationMs)).rounded())
    }
}

import Foundation

/// Time stays attached to each bar; playback translates bars instead of resampling fixed columns.
struct ScrollingWaveformGeometry {
    let durationMs: Int64
    let width: Double
    let step: Double
    var spanMs: Double { Double(min(max(durationMs, 1), 60_000)) }
    var barDurationMs: Double { spanMs * step / max(width, 1) }

    func x(timeMs: Double, positionMs: Int64) -> Double {
        width / 2 + (timeMs - Double(positionMs)) / spanMs * width
    }

    func visibleBars(positionMs: Int64) -> ClosedRange<Int> {
        let left = Double(positionMs) - spanMs / 2
        let first = max(0, Int(floor(left / barDurationMs)))
        let last = max(first, min(Int(ceil(Double(max(durationMs, 0)) / barDurationMs)),
                                  Int(ceil((left + spanMs) / barDurationMs))))
        return first...last
    }

    func tappedPosition(x: Double, anchorMs: Int64) -> Int64 {
        clamped(Double(anchorMs) + (x / max(width, 1) - 0.5) * spanMs)
    }

    func draggedPosition(translation: Double, anchorMs: Int64) -> Int64 {
        // Pull the waveform left to move forward; the time under the centre is selected.
        clamped(Double(anchorMs) - translation / max(width, 1) * spanMs)
    }

    private func clamped(_ value: Double) -> Int64 {
        Int64(min(max(value, 0), Double(max(durationMs, 0))).rounded())
    }
}

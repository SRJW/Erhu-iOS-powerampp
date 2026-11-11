import Foundation

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
    checks += 1
}
let geometry = ScrollingWaveformGeometry(durationMs: 240_000, width: 360, step: 9)
check(geometry.tappedPosition(x: 180, anchorMs: 100_000) == 100_000, "Centre tap keeps the current time")
check(geometry.tappedPosition(x: 360, anchorMs: 100_000) == 130_000, "Right tap advances")
check(geometry.tappedPosition(x: 0, anchorMs: 100_000) == 70_000, "Left tap rewinds")
check(geometry.draggedPosition(translation: -180, anchorMs: 100_000) == 130_000, "Pull left advances under the fixed playhead")
check(geometry.draggedPosition(translation: 180, anchorMs: 100_000) == 70_000, "Pull right rewinds")
check(geometry.draggedPosition(translation: -90, anchorMs: 100_000) == 115_000, "Dragging uses translation, not finger start location")
check(geometry.draggedPosition(translation: 0, anchorMs: 100_000) == 100_000, "Returning the finger cancels its displacement")
check(geometry.draggedPosition(translation: 9000, anchorMs: 100_000) == 0, "Clamp before track start")
check(geometry.draggedPosition(translation: -9000, anchorMs: 100_000) == 240_000, "Clamp after track end")
check(geometry.tappedPosition(x: -9000, anchorMs: 100_000) == 0, "Clamp out-of-bounds tap")
let short = ScrollingWaveformGeometry(durationMs: 12_000, width: 360, step: 9)
check(short.spanMs == 12_000, "Short songs use their actual duration")
check(short.draggedPosition(translation: -180, anchorMs: 0) == 6000, "Short-song drag scale")
let empty = ScrollingWaveformGeometry(durationMs: 0, width: 0, step: 9)
check(empty.draggedPosition(translation: 90, anchorMs: 0) == 0, "Unknown duration is safe")
check(geometry.x(timeMs: 100_000, positionMs: 100_000) == 180, "Current time is centred")
let before = geometry.x(timeMs: 110_000, positionMs: 100_000)
let after = geometry.x(timeMs: 110_000, positionMs: 100_100)
check(abs((after - before) + 0.6) < 0.00001, "Bars move subpixel distances instead of jumping columns")
check(geometry.visibleBars(positionMs: 0).lowerBound == 0, "No fabricated bars before the song")
for position: Int64 in [0, 1000, 60_000, 120_000, 239_999, 240_000] {
    let indices = geometry.visibleBars(positionMs: position)
    check(indices.count <= 43, "Drawing stays bounded to visible bars")
}
print("Passed \(checks) scrolling waveform checks")

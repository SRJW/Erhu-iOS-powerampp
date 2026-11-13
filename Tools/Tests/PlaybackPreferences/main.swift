import Foundation

var checks = 0
func check(_ value: @autoclosure () -> Bool, _ message: String) {
    precondition(value(), message)
    checks += 1
}
let waveform = FullTrackWaveformGeometry(durationMs: 240_000, width: 360)
check(waveform.position(at: 0) == 0, "Static left edge is the beginning")
check(waveform.position(at: 180) == 120_000, "Static midpoint is half the complete song")
check(waveform.position(at: 360) == 240_000, "Static right edge is the end")
check(waveform.position(at: -50) == 0, "Dragging before the file clamps")
check(waveform.position(at: 500) == 240_000, "Dragging beyond the file clamps")
check(waveform.position(at: .nan) == 0, "Invalid coordinates are safe")
check(FullTrackWaveformGeometry(durationMs: 0, width: 0).position(at: 10) == 0, "Unloaded waveform is safe")
check(PlaybackPreferences.handoffDuration(requested: 5000, outgoingRemaining: 20_000, incomingRemaining: 30_000) == 5000, "Manual crossfade uses the chosen duration")
check(PlaybackPreferences.handoffDuration(requested: 5000, outgoingRemaining: 900, incomingRemaining: 30_000) == 900, "Fit the outgoing tail")
check(PlaybackPreferences.handoffDuration(requested: 5000, outgoingRemaining: 20_000, incomingRemaining: 500) == 500, "Fit short incoming songs")
check(PlaybackPreferences.handoffDuration(requested: 0, outgoingRemaining: 20_000, incomingRemaining: 30_000) == 20, "Off preserves the inaudible anti-click handover")
check(PlaybackPreferences.handoffDuration(requested: 5000, outgoingRemaining: -1, incomingRemaining: 30_000) == 1, "Finished tracks cannot create a long phantom fade")
print("Passed \(checks) playback preference and static waveform checks")

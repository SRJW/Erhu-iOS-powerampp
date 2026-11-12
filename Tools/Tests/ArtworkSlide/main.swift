import Foundation

struct Frame: Identifiable { let id: Int; var payload: String? = nil }
var checks = 0
func check(_ value: @autoclosure () -> Bool, _ message: String) {
    guard value() else { fatalError(message) }
    checks += 1
}
var scene = ArtworkSlideQueue<Frame>()
check(!scene.offer(Frame(id: 1), direction: 1), "Initial cover does not slide in from an empty screen")
check(scene.current?.id == 1 && scene.outgoing == nil, "Initial cover is retained")
check(scene.offer(Frame(id: 2), direction: 1), "Next track starts a transition")
check(scene.current?.id == 2 && scene.outgoing?.id == 1, "Keep both actual covers during the slide")
check(!scene.offer(Frame(id: 3), direction: 1), "Rapid skipping leaves the current pair intact")
scene.offer(Frame(id: 4), direction: -1)
check(scene.pending?.frame.id == 4, "Retain only the latest pending cover")
check(scene.current?.id == 2 && scene.outgoing?.id == 1, "Do not replace a partially visible layer")
check(scene.finish(), "Finishing starts the pending transition")
check(scene.current?.id == 4 && scene.outgoing?.id == 2 && scene.direction == -1, "Pending destination retains its direction")
check(scene.pending == nil, "No unbounded queue of decoded images")
check(!scene.finish() && scene.outgoing == nil && scene.current?.id == 4, "Release the outgoing image when settled")
check(!scene.offer(Frame(id: 4), direction: 1), "Repeated current cover does not restart the effect")
scene.offer(Frame(id: 5), direction: 1)
scene.offer(Frame(id: 6), direction: 1)
scene.offer(Frame(id: 5), direction: -1)
check(scene.pending == nil, "Returning to the arriving cover clears an obsolete pending destination")
scene.offer(Frame(id: 7), direction: -1)
scene.settleImmediately()
check(scene.current?.id == 7 && scene.outgoing == nil && scene.pending == nil, "Closing the player or reducing motion settles at the latest cover")
for progress in [0.0, 0.1, 0.5, 0.9, 1.0] {
    for incoming in [false, true] {
        let next = ArtworkSlidePose.sample(progress: progress, direction: 1, incoming: incoming)
        let previous = ArtworkSlidePose.sample(progress: progress, direction: -1, incoming: incoming)
        check(abs(next.x + previous.x) < 0.00001, "Previous mirrors next, including queue wraparound")
        check(next.opacity >= 0 && next.opacity <= 1, "Cover blend weights stay bounded")
        check(next.scale >= 0.97 && next.scale <= 1.001, "Gentle cover scale stays bounded")
    }
}
check(ArtworkSlidePose.sample(progress: 0, direction: 1, incoming: false).x == 0, "Departing cover starts at the visible position")
let arrivalOffset = ArtworkSlidePose.sample(progress: 0, direction: 1, incoming: true).x
check(arrivalOffset == 0, "New cover keeps the same fixed frame without a lateral offset")
check(ArtworkSlidePose.sample(progress: 1, direction: 1, incoming: true).x == 0, "Incoming cover settles without a leftover offset")
check(ArtworkSlidePose.sample(progress: 5, direction: -1, incoming: true).x == 0, "Clamp completion overshoot")
let halfIn = ArtworkSlidePose.sample(progress: 0.5, direction: 1, incoming: true)
let halfOut = ArtworkSlidePose.sample(progress: 0.5, direction: 1, incoming: false)
check(halfIn.opacity == 0.5 && halfOut.opacity == 1, "Mid-transition blends over a fully covered base")
for progress in [0.0, 0.25, 0.5, 0.75, 1.0] {
    let incoming = ArtworkSlidePose.sample(progress: progress, direction: 1, incoming: true)
    let outgoing = ArtworkSlidePose.sample(progress: progress, direction: 1, incoming: false)
    let coverage = incoming.opacity + outgoing.opacity * (1 - incoming.opacity)
    check(abs(coverage - 1) < 0.00001, "The dissolve must never expose the backdrop")
    check(outgoing.x == 0 && outgoing.scale == 1, "The base stays stationary and fills the cover bounds")
}
check(ArtworkSwipeIntent.direction(translation: -100, velocity: 0, width: 400, canNext: true, canPrevious: false) == 1, "Left swipe advances")
check(ArtworkSwipeIntent.direction(translation: 100, velocity: 0, width: 400, canNext: false, canPrevious: true) == -1, "Right swipe goes back")
check(ArtworkSwipeIntent.direction(translation: -10, velocity: -900, width: 400, canNext: true, canPrevious: true) == 0, "Tiny finger motion does not skip")
check(ArtworkSwipeIntent.direction(translation: -30, velocity: -900, width: 400, canNext: true, canPrevious: true) == 1, "Deliberate short flick advances")
check(ArtworkSwipeIntent.direction(translation: -100, velocity: -900, width: 400, canNext: false, canPrevious: true) == 0, "A queue boundary does not skip")
check(ArtworkSwipeIntent.direction(translation: .nan, velocity: 0, width: 400, canNext: true, canPrevious: true) == 0, "Reject invalid gesture input")
print("Passed \(checks) cover transition checks")

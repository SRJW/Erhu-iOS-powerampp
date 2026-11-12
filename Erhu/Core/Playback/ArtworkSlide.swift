import Foundation

/// Keep an in-flight pair intact. Repeated skips replace a single pending destination.
struct ArtworkSlideQueue<Frame: Identifiable> {
    private(set) var current: Frame?
    private(set) var outgoing: Frame?
    private(set) var pending: (frame: Frame, direction: Int)?
    private(set) var direction = 1
    var moving: Bool { outgoing != nil }

    @discardableResult
    mutating func offer(_ frame: Frame, direction: Int) -> Bool {
        if frame.id == current?.id { pending = nil; return false }
        if moving { pending = (frame, direction); return false }
        outgoing = current
        current = frame
        self.direction = direction < 0 ? -1 : 1
        return moving
    }

    @discardableResult
    mutating func finish() -> Bool {
        outgoing = nil
        guard let next = pending else { return false }
        pending = nil
        return offer(next.frame, direction: next.direction)
    }

    mutating func settleImmediately() {
        if let pending { current = pending.frame }
        outgoing = nil
        pending = nil
    }
}

struct ArtworkSlidePose {
    let x: Double
    let scale: Double
    let opacity: Double

    static func sample(progress: Double, direction: Int, incoming: Bool) -> Self {
        let p = min(max(progress, 0), 1)
        let sign = direction < 0 ? -1.0 : 1.0
        return incoming
            ? Self(x: sign * (1 - p), scale: 0.98 + 0.02 * p, opacity: 0.8 + 0.2 * p)
            : Self(x: -sign * p, scale: 1 - 0.02 * p, opacity: 1 - 0.2 * p)
    }
}

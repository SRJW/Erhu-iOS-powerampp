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
        // Keep a fully covered base throughout the dissolve. Fading both layers
        // exposes the backdrop and creates a visible dip in brightness halfway.
        return incoming
            ? Self(x: sign * (1 - p) * 0.012, scale: 0.99 + 0.01 * p, opacity: p)
            : Self(x: 0, scale: 1, opacity: 1)
    }
}

/// Commit only a deliberate horizontal swipe; keep vertical dismissal independent.
enum ArtworkSwipeIntent {
    static func direction(translation: Double, velocity: Double, width: Double,
                          canNext: Bool, canPrevious: Bool) -> Int {
        guard translation.isFinite, velocity.isFinite, width.isFinite, width > 0 else { return 0 }
        let deliberate = abs(translation) >= width * 0.18 || (abs(translation) >= 20 && abs(velocity) >= 650 && translation * velocity > 0)
        guard deliberate else { return 0 }
        if translation < 0 && canNext { return 1 }
        if translation > 0 && canPrevious { return -1 }
        return 0
    }
}

import SwiftUI

/// The track's real amplitude envelope as a seek bar: the played part in the accent, bookmark
/// ticks along the bottom and the A–B loop region. Tap to seek; drag to preview and seek once on
/// release. A flat placeholder shows while the waveform loads (or when the file has none).
struct WaveformSeekBar: View {
    let levels: [Float]?
    let positionMs: Int64
    let durationMs: Int64
    let bookmarks: [Int64]
    let loop: AbLoopState?
    @Binding var previewMs: Int64?
    let onSeek: (Int64) -> Void
    var referenceStyle = false
    var barHeight: CGFloat = 56
    @Environment(\.palette) private var palette

    private static let barWidth: CGFloat = 3
    private static let barGap: CGFloat = 2

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                draw(in: &context, size: size)
            }
            .clipped()
            .allowsHitTesting(false)
            .overlay {
                SeekInteraction(preview: { x in previewMs = x.map { position(at: $0, width: geometry.size.width) } },
                                commit: { onSeek(position(at: $0, width: geometry.size.width)) })
            }
        }
        .frame(height: barHeight)
        .accessibilityElement()
        .accessibilityLabel("Seek")
        .accessibilityValue("\(formatDuration(positionMs)) of \(formatDuration(durationMs))")
        .accessibilityAdjustableAction { direction in
            let step: Int64 = 10_000
            switch direction {
            case .increment: onSeek(min(positionMs + step, durationMs))
            case .decrement: onSeek(max(positionMs - step, 0))
            @unknown default: break
            }
        }
    }

    private func position(at x: CGFloat, width: CGFloat) -> Int64 {
        guard width > 0 else { return 0 }
        let span = min(1, 60_000 / Double(max(durationMs, 1)))
        let fraction = referenceStyle
            ? Double(positionMs) / Double(max(durationMs, 1)) + (Double(x / width) - 0.5) * span
            : Double(x / width)
        return WaveformTimeline.positionAt(Float(min(max(fraction, 0), 1)), durationMs)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let barWidth: CGFloat = referenceStyle ? 7 : Self.barWidth
        let step = barWidth + Self.barGap
        let count = max(Int((size.width + Self.barGap) / step), 1)
        let fraction = CGFloat(WaveformTimeline.fractionOf(previewMs ?? positionMs, durationMs))
        let span = CGFloat(min(1, 60_000 / Double(max(durationMs, 1))))
        let bars: [Float] = referenceStyle ? (0..<count).map { index in
            let f = fraction + (CGFloat(index) / CGFloat(count) - 0.5) * span
            guard f >= 0, f <= 1 else { return 0 }
            guard let levels, !levels.isEmpty else { return 0.12 }
            let start = min(Int(f * CGFloat(levels.count)), levels.count - 1)
            let end = min(max(start + Int(span * CGFloat(levels.count) / CGFloat(count)), start + 1), levels.count)
            return levels[start..<end].max() ?? 0
        } : Self.barLevels(levels, count)
        func timelineX(_ f: CGFloat) -> CGFloat {
            referenceStyle ? size.width * (0.5 + (f - fraction) / span) : f * size.width
        }
        let playedX = referenceStyle ? size.width / 2 : fraction * size.width
        if let loop {
            let start = loop.startMs.map { timelineX(CGFloat(WaveformTimeline.fractionOf($0, durationMs))) }
            let end = loop.endMs.map { timelineX(CGFloat(WaveformTimeline.fractionOf($0, durationMs))) }
            if let start, let end, end > start {
                context.fill(Path(CGRect(x: start, y: 0, width: end - start, height: size.height)),
                             with: .color(palette.onSurfaceVariant.opacity(loop.enabled ? 0.16 : 0.07)))
            }
            for x in [start, end].compactMap({ $0 }) {
                context.fill(Path(CGRect(x: x - 1, y: 0, width: 2, height: size.height)), with: .color(palette.onSurfaceVariant))
            }
        }
        for (i, level) in bars.enumerated() {
            let x = CGFloat(i) * step
            let height = max(CGFloat(level) * size.height * (referenceStyle ? 0.75 : 1), 2)
            let rect = CGRect(x: x, y: (size.height - height) / 2, width: barWidth, height: height)
            let color = referenceStyle
                ? Color.white.opacity(x + barWidth / 2 <= playedX ? 0.25 : 0.70)
                : (x + barWidth / 2 <= playedX ? palette.primary : palette.onSurfaceVariant.opacity(0.35))
            context.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: .color(color))
        }
        if referenceStyle {
            context.fill(Path(CGRect(x: size.width / 2 - 0.5, y: 0, width: 1, height: size.height)), with: .color(.white.opacity(0.75)))
        }
        for ms in bookmarks {
            let x = timelineX(CGFloat(WaveformTimeline.fractionOf(ms, durationMs)))
            context.fill(Path(ellipseIn: CGRect(x: x - 2.5, y: size.height - 5, width: 5, height: 5)), with: .color(palette.onSurface))
        }
    }

    /// [count] bar heights 0..1 (the loudest level of each slice), or a flat placeholder.
    static func barLevels(_ levels: [Float]?, _ count: Int) -> [Float] {
        guard let levels, !levels.isEmpty else { return Array(repeating: 0.12, count: count) }
        return (0..<count).map { bar in
            let from = bar * levels.count / count
            let to = min(max((bar + 1) * levels.count / count, from + 1), levels.count)
            return levels[from..<to].max() ?? 0
        }
    }
}

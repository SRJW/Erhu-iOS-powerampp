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
    @State private var scrubAnchorMs: Int64?
    var barHeight: CGFloat = 56
    @Environment(\.palette) private var palette
    @Environment(\.playerReduceMotion) private var reduceMotion

    private static let barWidth: CGFloat = 3
    private static let barGap: CGFloat = 2

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                draw(in: &context, size: size)
            }
            .scaleEffect(x: 1, y: referenceStyle && levels == nil ? 0.12 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: levels == nil)
            .clipped()
            .allowsHitTesting(false)
            .overlay {
                if referenceStyle {
                    PanInteraction(canBegin: { _, delta in HorizontalGestureIntent.accepts(delta) },
                        change: { sample in
                            if scrubAnchorMs == nil { scrubAnchorMs = positionMs }
                            previewMs = scrollingGeometry(geometry.size.width).draggedPosition(
                                translation: Double(sample.translation.width), anchorMs: scrubAnchorMs ?? positionMs)
                        }, end: { sample in
                            let target = scrollingGeometry(geometry.size.width).draggedPosition(
                                translation: Double(sample.translation.width), anchorMs: scrubAnchorMs ?? positionMs)
                            onSeek(target)
                            previewMs = nil
                            scrubAnchorMs = nil
                        }, cancel: {
                            previewMs = nil
                            scrubAnchorMs = nil
                        }, tap: { point in
                            onSeek(scrollingGeometry(geometry.size.width).tappedPosition(x: Double(point.x), anchorMs: positionMs))
                            scrubAnchorMs = nil
                        })
                } else {
                    SeekInteraction(preview: { x in previewMs = x.map { position(at: $0, width: geometry.size.width) } },
                                    commit: { onSeek(position(at: $0, width: geometry.size.width)) })
                }
            }
        }
        .overlay {
            if referenceStyle {
                Rectangle().fill(.white.opacity(0.7))
                    .frame(width: 1)
                    .opacity(previewMs == nil ? 0 : 1)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.16)
                        .delay(previewMs == nil ? 0 : 0.30), value: previewMs != nil)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .frame(height: barHeight)
        .accessibilityElement()
        .accessibilityLabel("Seek")
        .accessibilityIdentifier(referenceStyle ? "nowPlayingWaveform" : "waveformSeek")
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
        return WaveformTimeline.positionAt(Float(min(max(x / width, 0), 1)), durationMs)
    }

    private func scrollingGeometry(_ width: CGFloat) -> ScrollingWaveformGeometry {
        ScrollingWaveformGeometry(durationMs: durationMs, width: Double(width), step: 9)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let barWidth: CGFloat = referenceStyle ? 7 : Self.barWidth
        let step = barWidth + Self.barGap
        let count = max(Int((size.width + Self.barGap) / step), 1)
        let fraction = CGFloat(WaveformTimeline.fractionOf(previewMs ?? positionMs, durationMs))
        let span = CGFloat(min(1, 60_000 / Double(max(durationMs, 1))))
        let bars = referenceStyle ? [] : Self.barLevels(levels, count)
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
        if referenceStyle {
            let geometry = scrollingGeometry(size.width)
            let position = previewMs ?? positionMs
            for index in geometry.visibleBars(positionMs: position) {
                let time = Double(index) * geometry.barDurationMs
                guard time <= Double(durationMs) else { continue }
                let x = CGFloat(geometry.x(timeMs: time, positionMs: position))
                let level: Float
                if let levels, !levels.isEmpty {
                    let from = min(Int(time / Double(max(durationMs, 1)) * Double(levels.count)), levels.count - 1)
                    let to = min(max(from + 1, Int((time + geometry.barDurationMs) / Double(max(durationMs, 1)) * Double(levels.count))), levels.count)
                    level = levels[from..<to].max() ?? 0
                } else { level = 0.12 }
                let height = max(CGFloat(level) * size.height * 0.75, 2)
                let rect = CGRect(x: x - barWidth / 2, y: (size.height - height) / 2, width: barWidth, height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2),
                             with: .color(.white.opacity(x <= playedX ? 0.25 : 0.70)))
            }
        } else {
            for (i, level) in bars.enumerated() {
                let x = CGFloat(i) * step
                let height = max(CGFloat(level) * size.height, 2)
                let rect = CGRect(x: x, y: (size.height - height) / 2, width: barWidth, height: height)
                let color = x + barWidth / 2 <= playedX ? palette.primary : palette.onSurfaceVariant.opacity(0.35)
                context.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: .color(color))
            }
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

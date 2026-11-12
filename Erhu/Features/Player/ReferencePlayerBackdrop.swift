import SwiftUI
import UIKit

private struct ArtworkSlideFrame: Identifiable {
    let id: String
    let image: UIImage?
    let dominant: Color
}

struct ReferencePlayerBackdrop: View {
    let song: Song?
    @Binding var artworkDrag: Double
    @Environment(PlayerController.self) private var player
    @Environment(\.playerReduceMotion) private var reduceMotion
    @State private var frames = ArtworkSlideQueue<ArtworkSlideFrame>()
    @State private var progress = 1.0
    @State private var artworkRevision = 0
    @State private var settlement: Task<Void, Never>?
    @State private var nextCover: ArtworkSlideFrame?
    @State private var previousCover: ArtworkSlideFrame?
    @State private var neighbourOwner: String?
    @State private var lastDragDirection = 1
    private static let duration = 0.62

    private var dragDirection: Int { artworkDrag == 0 ? lastDragDirection : (artworkDrag < 0 ? 1 : -1) }
    private var dragProgress: Double { min(abs(artworkDrag), 1) }
    private var neighbour: ArtworkSlideFrame? {
        guard neighbourOwner == frames.current?.id else { return nil }
        return dragDirection > 0 ? nextCover : previousCover
    }
    private var base: Color { (frames.outgoing ?? frames.current)?.dominant ?? Color(argb: LyricsPalette.fallback.artworkDominant) }
    private var target: Color? { frames.moving ? frames.current?.dominant : neighbour?.dominant }
    private var blend: Double { frames.moving ? progress : dragProgress }

    var body: some View {
        PlayerFullBleedBackground(dominant: base, secondaryDominant: target, blend: blend) {
            GeometryReader { geometry in
                ZStack {
                    if frames.moving {
                        if let outgoing = frames.outgoing { cover(outgoing, size: geometry.size, incoming: false, amount: progress, direction: frames.direction) }
                        if let current = frames.current { cover(current, size: geometry.size, incoming: true, amount: progress, direction: frames.direction) }
                    } else {
                        if let current = frames.current { cover(current, size: geometry.size, incoming: false, amount: dragProgress, direction: dragDirection) }
                        if let neighbour { cover(neighbour, size: geometry.size, incoming: true, amount: dragProgress, direction: dragDirection) }
                    }
                }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
            }
        }
        .onChange(of: artworkDrag) { _, value in
            if value != 0 { lastDragDirection = value < 0 ? 1 : -1 }
        }
        .onReceive(NotificationCenter.default.publisher(for: ArtworkLoader.didChange)) { note in
            if note.object as? String == song?.url.path { artworkRevision += 1 }
        }
        .task(id: "\(player.state.currentEntry?.id.uuidString ?? "")|\(song?.url.path ?? "")|\(artworkRevision)") {
            let direction = player.artworkDirection
            guard let url = song?.url else { settle(); frames = ArtworkSlideQueue(); return }
            guard let frame = await load(url), !Task.isCancelled else { return }
            let start = direction == dragDirection ? dragProgress : 0
            let began = frames.offer(frame, direction: direction)
            if began { animatePair(from: start) }
            else if !frames.moving {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.24)) { artworkDrag = 0 }
                progress = 1
            }
            // Decode only the two adjacent covers, outside the gesture's input callbacks.
            let state = player.state
            let next = PlayOrder.next(after: state.currentIndex, count: state.queue.count, repeatMode: state.repeatMode, userSkip: true)
            let previous = PlayOrder.previous(before: state.currentIndex, count: state.queue.count, repeatMode: state.repeatMode)
            let nextURL = next.flatMap { state.queue.indices.contains($0) ? state.queue[$0].song.url : nil }
            let previousURL = previous.flatMap { state.queue.indices.contains($0) ? state.queue[$0].song.url : nil }
            async let nextFrame = loadOptional(nextURL)
            async let previousFrame = loadOptional(previousURL)
            let (newNext, newPrevious) = await (nextFrame, previousFrame)
            guard !Task.isCancelled else { return }
            nextCover = newNext
            previousCover = newPrevious
            neighbourOwner = frame.id
        }
        .onChange(of: reduceMotion) { _, _ in settle() }
        .onDisappear { settle() }
    }

    private func loadOptional(_ url: URL?) async -> ArtworkSlideFrame? {
        guard let url else { return nil }
        return await load(url)
    }

    private func load(_ url: URL) async -> ArtworkSlideFrame? {
        let revision = ArtworkLoader.shared.revision(for: url.path)
        async let image = ArtworkLoader.shared.image(for: url, maxPixels: 1600)
        async let colors = LyricsPaletteCache.shared.palette(for: url)
        let (loaded, sampled) = await (image, colors)
        guard !Task.isCancelled, revision == ArtworkLoader.shared.revision(for: url.path) else { return nil }
        return ArtworkSlideFrame(id: "\(url.path)|\(revision)", image: loaded, dominant: Color(argb: sampled.artworkDominant))
    }

    private func cover(_ frame: ArtworkSlideFrame, size: CGSize, incoming: Bool, amount: Double, direction: Int) -> some View {
        ArtworkSlideLayer(progress: amount, direction: direction, incoming: incoming,
                          reduceMotion: reduceMotion, size: size) {
            ZStack {
                if let image = frame.image { Image(uiImage: image).resizable().scaledToFill() }
                else {
                    frame.dominant
                    Image(systemName: "music.note").font(.system(size: 20)).foregroundStyle(.white.opacity(0.2))
                }
            }
        }
    }

    private func animatePair(from start: Double = 0) {
        settlement?.cancel()
        let duration = reduceMotion ? 0.18 : max(0.18, Self.duration * (1 - start))
        let animation: Animation = reduceMotion ? .easeInOut(duration: duration)
            : .timingCurve(0.33, 0, 0.2, 1, duration: duration)
        var instant = Transaction(animation: nil); instant.disablesAnimations = true
        withTransaction(instant) { progress = start; artworkDrag = 0 }
        settlement = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
            withAnimation(animation) { progress = 1 }
            do { try await Task.sleep(for: .seconds(duration)) } catch { return }
            var instant = Transaction(animation: nil); instant.disablesAnimations = true
            var another = false
            withTransaction(instant) { another = frames.finish() }
            if another { animatePair() }
            else { settlement = nil }
        }
    }

    private func settle() {
        settlement?.cancel(); settlement = nil
        var instant = Transaction(animation: nil); instant.disablesAnimations = true
        withTransaction(instant) { frames.settleImmediately(); progress = 1; artworkDrag = 0 }
    }
}

import SwiftUI
import UIKit

private struct ArtworkSlideFrame: Identifiable {
    let id: String
    let image: UIImage?
    let palette: PlayerArtworkPalette
}

struct ReferencePlayerBackdrop: View {
    let song: Song?
    @Binding var artworkDrag: Double
    @Environment(PlayerController.self) private var player
    @Environment(\.playerReduceMotion) private var reduceMotion
    @State private var frames = ArtworkSlideQueue<ArtworkSlideFrame>()
    @State private var progress = 1.0
    @State private var colourProgress = 1.0
    @State private var artworkRevision = 0
    @State private var settlement: Task<Void, Never>?
    @State private var nextCover: ArtworkSlideFrame?
    @State private var previousCover: ArtworkSlideFrame?
    @State private var neighbourOwner: String?
    @State private var lastDragDirection = 1
    private static let duration = 0.88

    private var dragDirection: Int { artworkDrag == 0 ? lastDragDirection : (artworkDrag < 0 ? 1 : -1) }
    private var dragProgress: Double { min(abs(artworkDrag), 1) }
    private var neighbour: ArtworkSlideFrame? {
        guard neighbourOwner == frames.current?.id else { return nil }
        return dragDirection > 0 ? nextCover : previousCover
    }
    private var base: PlayerArtworkPalette { (frames.outgoing ?? frames.current)?.palette ?? .missing }
    private var target: PlayerArtworkPalette? { frames.moving ? frames.current?.palette : neighbour?.palette }
    private var blend: Double { frames.moving ? progress : dragProgress }
    private var colourBlend: Double { frames.moving ? colourProgress : dragProgress }
    private var outgoingCover: ArtworkSlideFrame? { frames.moving ? frames.outgoing : frames.current }
    private var incomingCover: ArtworkSlideFrame? { frames.moving ? frames.current : neighbour }
    private var visibleDirection: Int { frames.moving ? frames.direction : dragDirection }

    var body: some View {
        GeometryReader { viewport in
            PlayerFullBleedBackground(palette: base, secondaryPalette: target, blend: colourBlend) {
                GeometryReader { geometry in
                    ZStack {
                        // Keep the same two layer slots when a drag becomes a committed skip.
                        // Replacing conditional branches here discards their presentation state.
                        if let outgoingCover { cover(outgoingCover, size: geometry.size, incoming: false, amount: blend, direction: visibleDirection) }
                        if let incomingCover { cover(incomingCover, size: geometry.size, incoming: true, amount: blend, direction: visibleDirection) }
                    }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
                }
            }
            .onChange(of: artworkDrag) { _, value in
                if value != 0 { lastDragDirection = value < 0 ? 1 : -1 }
            }
            .onReceive(NotificationCenter.default.publisher(for: ArtworkLoader.didChange)) { note in
                if note.object as? String == song?.url.path { artworkRevision += 1 }
            }
            .task(id: "\(player.state.currentEntry?.id.uuidString ?? "")|\(song?.url.path ?? "")|\(artworkRevision)|\(Int(viewport.size.width))x\(Int(viewport.size.height))") {
                let direction = player.artworkDirection
                guard let url = song?.url else { settle(); frames = ArtworkSlideQueue(); return }
                let aspect = Double(viewport.size.width / max(viewport.size.height * PlayerReferenceStyle.coverHeightFraction, 1))
                let expectedID = "\(url.path)|\(ArtworkLoader.shared.revision(for: url.path))|\(Int((aspect * 10_000).rounded()))"
                // A swipe already displays this decoded cover. Reuse it without waiting for
                // another asynchronous load while the released finger's frame is held still.
                let cached = [nextCover, previousCover].compactMap { $0 }.first { $0.id == expectedID }
                let loaded = cached == nil ? await load(url, aspect: aspect) : cached
                guard let frame = loaded, !Task.isCancelled else { return }
                let start = direction == dragDirection ? dragProgress : 0
                let began = frames.offer(frame, direction: direction)
                if began { animatePair(from: start) }
                else if !frames.moving {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.24)) { artworkDrag = 0 }
                    progress = 1
                    colourProgress = 1
                }
                // Decode only the two adjacent covers, outside the gesture's input callbacks.
                let state = player.state
                let next = PlayOrder.next(after: state.currentIndex, count: state.queue.count, repeatMode: state.repeatMode, userSkip: true)
                let previous = PlayOrder.previous(before: state.currentIndex, count: state.queue.count, repeatMode: state.repeatMode)
                let nextURL = next.flatMap { state.queue.indices.contains($0) ? state.queue[$0].song.url : nil }
                let previousURL = previous.flatMap { state.queue.indices.contains($0) ? state.queue[$0].song.url : nil }
                async let nextFrame = loadOptional(nextURL, aspect: aspect)
                async let previousFrame = loadOptional(previousURL, aspect: aspect)
                let (newNext, newPrevious) = await (nextFrame, previousFrame)
                guard !Task.isCancelled else { return }
                nextCover = newNext
                previousCover = newPrevious
                neighbourOwner = frame.id
            }
            .onChange(of: reduceMotion) { _, _ in settle() }
            .onDisappear { settle() }
        }
    }

    private func loadOptional(_ url: URL?, aspect: Double) async -> ArtworkSlideFrame? {
        guard let url else { return nil }
        return await load(url, aspect: aspect)
    }

    private func load(_ url: URL, aspect: Double) async -> ArtworkSlideFrame? {
        let revision = ArtworkLoader.shared.revision(for: url.path)
        let loaded = await ArtworkLoader.shared.image(for: url, maxPixels: 1600)
        let sampled = await PlayerArtworkPaletteCache.shared.palette(for: url, image: loaded, revision: revision, aspect: aspect)
        guard !Task.isCancelled, revision == ArtworkLoader.shared.revision(for: url.path) else { return nil }
        return ArtworkSlideFrame(id: "\(url.path)|\(revision)|\(Int((aspect * 10_000).rounded()))", image: loaded, palette: sampled)
    }

    private func cover(_ frame: ArtworkSlideFrame, size: CGSize, incoming: Bool, amount: Double, direction: Int) -> some View {
        ArtworkSlideLayer(progress: amount, direction: direction, incoming: incoming,
                          reduceMotion: reduceMotion, size: size,
                          outgoingLuminance: base.topLuminance, incomingLuminance: frame.palette.topLuminance) {
            ZStack {
                if let image = frame.image { Image(uiImage: image).resizable().scaledToFill() }
                else {
                    Color(argb: frame.palette.source)
                    Image(systemName: "music.note").font(.system(size: 20)).foregroundStyle(.white.opacity(0.2))
                }
            }
        }
    }

    private func animatePair(from start: Double = 0) {
        settlement?.cancel()
        let duration = reduceMotion ? 0.18 : max(0.18, Self.duration * (1 - start))
        let colourDuration = min(duration, PlayerReferenceStyle.colourTransitionDuration * (1 - start))
        let animation: Animation = reduceMotion ? .easeInOut(duration: duration)
            : start > 0 ? .timingCurve(0.16, 1, 0.3, 1, duration: duration)
            : .timingCurve(0.42, 0, 0.58, 1, duration: duration)
        var instant = Transaction(animation: nil); instant.disablesAnimations = true
        withTransaction(instant) { progress = start; colourProgress = start; artworkDrag = 0 }
        settlement = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
            withAnimation(animation) { progress = 1 }
            withAnimation(.easeInOut(duration: colourDuration)) {
                colourProgress = 1
            }
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
        withTransaction(instant) { frames.settleImmediately(); progress = 1; colourProgress = 1; artworkDrag = 0 }
    }
}

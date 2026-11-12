import SwiftUI
import UIKit

private struct ArtworkSlideFrame: Identifiable {
    let id: String
    let image: UIImage?
    let dominant: Color
}

struct ReferencePlayerBackdrop: View {
    let song: Song?
    @Environment(PlayerController.self) private var player
    @Environment(\.playerReduceMotion) private var reduceMotion
    @State private var frames = ArtworkSlideQueue<ArtworkSlideFrame>()
    @State private var progress = 1.0
    @State private var dominant = Color(argb: LyricsPalette.fallback.artworkDominant)
    @State private var artworkRevision = 0
    @State private var settlement: Task<Void, Never>?
    private static let duration = 0.42

    var body: some View {
        PlayerFullBleedBackground(dominant: dominant) {
            GeometryReader { geometry in
                ZStack {
                    if let outgoing = frames.outgoing {
                        cover(outgoing, size: geometry.size, incoming: false)
                    }
                    if let current = frames.current {
                        cover(current, size: geometry.size, incoming: true)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: ArtworkLoader.didChange)) { note in
            if note.object as? String == song?.url.path { artworkRevision += 1 }
        }
        .task(id: "\(song?.url.path ?? "")|\(artworkRevision)") {
            let direction = player.artworkDirection
            guard let url = song?.url else {
                settlement?.cancel()
                frames = ArtworkSlideQueue()
                progress = 1
                dominant = Color(argb: LyricsPalette.fallback.artworkDominant)
                return
            }
            let revision = ArtworkLoader.shared.revision(for: url.path)
            async let image = ArtworkLoader.shared.image(for: url, maxPixels: 1600)
            async let colors = LyricsPaletteCache.shared.palette(for: url)
            let (loaded, sampled) = await (image, colors)
            guard !Task.isCancelled, revision == ArtworkLoader.shared.revision(for: url.path) else { return }
            let frame = ArtworkSlideFrame(id: "\(url.path)|\(revision)", image: loaded,
                                          dominant: Color(argb: sampled.artworkDominant))
            // Keep the departing cover visible until both the new image and its colour are ready.
            let began = frames.offer(frame, direction: direction)
            if began {
                animatePair()
            } else if !frames.moving {
                progress = 1
                dominant = frame.dominant
            }
        }
        .onChange(of: reduceMotion) { _, reduced in
            if reduced { settle() }
        }
        .onDisappear { settle() }
    }

    private func cover(_ frame: ArtworkSlideFrame, size: CGSize, incoming: Bool) -> some View {
        let pose = reduceMotion
            ? ArtworkSlidePose(x: 0, scale: 1, opacity: incoming ? progress : 1)
            : ArtworkSlidePose.sample(progress: progress, direction: frames.direction, incoming: incoming)
        return ZStack {
            if let image = frame.image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                frame.dominant
                Image(systemName: "music.note").font(.system(size: 20)).foregroundStyle(.white.opacity(0.2))
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .scaleEffect(CGFloat(1.10 * pose.scale))
        .opacity(pose.opacity)
        .offset(x: size.width * CGFloat(pose.x))
    }

    private func animatePair() {
        settlement?.cancel()
        let duration = reduceMotion ? 0.15 : Self.duration
        let animation: Animation = reduceMotion ? .easeInOut(duration: duration)
            : .timingCurve(0.22, 0, 0.2, 1, duration: duration)
        var instant = Transaction(animation: nil)
        instant.disablesAnimations = true
        withTransaction(instant) { progress = 0 }
        settlement = Task { @MainActor in
            // Mount the two layers at their initial positions before asking the compositor to slide.
            do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
            withAnimation(animation) {
                progress = 1
                if let current = frames.current { dominant = current.dominant }
            }
            do { try await Task.sleep(for: .seconds(duration)) } catch { return }
            var instant = Transaction(animation: nil)
            instant.disablesAnimations = true
            var another = false
            withTransaction(instant) { another = frames.finish() }
            if another { animatePair() }
            else { settlement = nil }
        }
    }

    private func settle() {
        settlement?.cancel()
        settlement = nil
        var instant = Transaction(animation: nil)
        instant.disablesAnimations = true
        withTransaction(instant) {
            frames.settleImmediately()
            progress = 1
            if let current = frames.current { dominant = current.dominant }
        }
    }
}

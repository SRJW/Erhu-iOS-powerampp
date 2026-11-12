import SwiftUI

/// Interpolate the source blend itself, so offset, opacity and scale share one visible phase.
struct ArtworkSlideLayer<Content: View>: View, Animatable {
    var progress: Double
    let direction: Int
    let incoming: Bool
    let reduceMotion: Bool
    let size: CGSize
    @ViewBuilder var content: () -> Content

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let pose = reduceMotion
            ? ArtworkSlidePose(x: 0, scale: 1, opacity: incoming ? progress : 1)
            : ArtworkSlidePose.sample(progress: progress, direction: direction, incoming: incoming)
        content()
            .frame(width: size.width, height: size.height).clipped()
            .scaleEffect(CGFloat(1.10 * pose.scale))
            .frame(width: size.width, height: size.height).clipped()
            .opacity(pose.opacity)
            .offset(x: size.width * CGFloat(pose.x))
    }
}

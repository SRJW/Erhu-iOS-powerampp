import SwiftUI

/// A stationary, full-size cover. Only its opacity changes between tracks.
struct ArtworkSlideLayer<Content: View>: View, Animatable {
    var progress: Double
    let direction: Int
    let incoming: Bool
    let reduceMotion: Bool
    let size: CGSize
    var outgoingLuminance: Double? = nil
    var incomingLuminance: Double? = nil
    @ViewBuilder var content: () -> Content

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var usesDarkStatusText: Bool {
        let amount = min(max(progress, 0), 1)
        let sourceLuminance = outgoingLuminance ?? 0
        let visibleLuminance = incoming ? sourceLuminance * (1 - amount) + (incomingLuminance ?? sourceLuminance) * amount : sourceLuminance
        return visibleLuminance > PlayerReferenceStyle.darkStatusThreshold
    }

    var body: some View {
        let amount = min(max(progress, 0), 1)
        content()
            .frame(width: size.width, height: size.height).clipped()
            .opacity(incoming ? amount : 1)
            .preference(key: PlayerStatusBarPreference.self,
                        value: usesDarkStatusText)
    }
}

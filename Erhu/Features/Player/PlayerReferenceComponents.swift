import SwiftUI
import UIKit
import AVFoundation

struct PlayerFullBleedBackground<Artwork: View>: View, Animatable {
    let dominant: Color
    var secondaryDominant: Color? = nil
    var blend = 0.0
    var appearance = PlayerBackgroundSettings()
    @ViewBuilder var artwork: () -> Artwork

    var animatableData: Double {
        get { blend }
        set { blend = newValue }
    }

    private func muted(_ color: Color) -> UIColor {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        guard UIColor(color).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return UIColor(red: 0.50, green: 0.31, blue: 0.29, alpha: 1)
        }
        let mutedHue = hue < 0.12 ? hue * 0.5 : hue
        return UIColor(hue: mutedHue, saturation: saturation * 0.55,
                       brightness: min(max(brightness, 0.50), 0.58), alpha: 1)
    }
    var body: some View {
        GeometryReader { geometry in
            let base = Color(uiColor: muted(dominant))
            ZStack(alignment: .top) {
                ZStack {
                    LinearGradient(colors: [base, base, base.opacity(0.18)],
                                   startPoint: .top, endPoint: .bottom)
                        .background(Color(red: 0.10, green: 0.045, blue: 0.035))
                    if let secondaryDominant {
                        let next = Color(uiColor: muted(secondaryDominant))
                        let phase = min(max(blend, 0), 1)
                        // Introduce the next palette near the cover first, then let
                        // it flow into the controls. Both ends settle to one colour.
                        let spread = 0.22 * sin(.pi * phase)
                        LinearGradient(colors: [next, next, next.opacity(0.18)], startPoint: .top, endPoint: .bottom)
                            .background(Color(red: 0.10, green: 0.045, blue: 0.035))
                            .mask {
                                LinearGradient(colors: [
                                    .white.opacity(min(phase + spread, 1)),
                                    .white.opacity(max(phase - spread, 0))
                                ], startPoint: .top, endPoint: .bottom)
                            }
                    }
                    if appearance.details > 0 {
                        artwork()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                            .blur(radius: appearance.blur)
                            .opacity(appearance.details * 0.45)
                    }
                    LinearGradient(colors: [.clear, Color(argb: appearance.gradientColor)], startPoint: .top, endPoint: .bottom)
                        .opacity(appearance.gradient)
                    Color.black.opacity(1 - appearance.intensity)
                }.saturation(appearance.saturation)
                artwork()
                    .frame(width: geometry.size.width, height: geometry.size.height * 0.55)
                    .clipped()
                    .mask {
                        LinearGradient(stops: [.init(color: .white, location: 0),
                                               .init(color: .white, location: appearance.fadeStart.clamped(0, 0.99)),
                                               .init(color: .clear, location: 1)],
                                       startPoint: .top, endPoint: .bottom)
                    }
                LinearGradient(colors: [.black.opacity(0.40), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: geometry.size.height * 0.12)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct PlayerEqualizerGlyph: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            RoundedRectangle(cornerRadius: 3).frame(width: 8, height: 8)
            RoundedRectangle(cornerRadius: 3).frame(width: 8, height: 28)
            RoundedRectangle(cornerRadius: 3).frame(width: 8, height: 20)
        }.frame(width: 30, height: 30)
    }
}
struct PlayerQueueGlyph: View {
    var body: some View {
        VStack(spacing: 4) {
            ForEach(0..<3) { _ in Capsule().frame(width: 27, height: 6) }
        }.frame(width: 32, height: 32)
    }
}

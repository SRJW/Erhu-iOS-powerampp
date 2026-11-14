import Foundation

/// Fractions of the full screen width (W) / height (H), independent of waveform insets.
enum PlayerLayoutMetrics {
    static let playDiameterW: CGFloat = 0.183
    static let pauseDiameterW: CGFloat = 0.166
    static let innerDiameterW: CGFloat = 0.15
    static let outerDiameterW: CGFloat = 0.11
    // Together with the diameters, these centres leave about 0.005 W between circles.
    static let transportCentresW: [CGFloat] = [0.192, 0.328, 0.5, 0.672, 0.808]
    static let transportCentreH: CGFloat = 0.79
    static let triangleWidthInCircle: CGFloat = 0.55

    static let secondaryCentresW: [CGFloat] = [0.12, 0.31, 0.5, 0.69, 0.88]
    static let secondaryCentreH: CGFloat = 0.675
    static let secondaryIconW: CGFloat = 0.05
    static let heartIconW: CGFloat = 0.052
    static let shareHeightInWidth: CGFloat = 1.15
    static let idleOpacity = 0.5

    static let titleScale: CGFloat = 0.82
    static let subtitleScale: CGFloat = 0.95
    static let timeBadgeW: CGFloat = 0.106
    static let timeTextScale: CGFloat = 0.92
    static let timeMinimumScale: CGFloat = 0.6
    static let timeBadgeHeight: CGFloat = 27
    static let technicalTextScale: CGFloat = 0.92
    static let technicalSeparator = " "

    static let navigationIconScale: CGFloat = 0.88
    static let navigationCentresW: [CGFloat] = [0.143, 0.381, 0.619, 0.857]
}

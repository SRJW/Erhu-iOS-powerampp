import Foundation
import SwiftUI
import UIKit

/// Player-only tuning. Transport, waveform, time labels and navigation positions stay unchanged.
enum PlayerReferenceStyle {
    static let coverHeightFraction: CGFloat = 0.57
    static let coverFadeStart: CGFloat = 0.75
    static let statusScrimHeight: CGFloat = 115
    static let statusScrimOpacity = 0.45
    static let topSampleFraction = 0.08
    static let bottomSampleFraction = 0.15
    static let darkStatusThreshold = 0.60
    static let colourTransitionDuration = 0.30
    static let paletteBlendSpread = 0.22
    static let brightnessMultiplier = 0.80
    static let maximumBrightness = 0.45
    static let minimumBrightness = 0.08
    static let bottomBrightnessMultiplier = 1.0 / 3.0
    static let minimumBottomBrightness = 0.12
    static let maximumBottomBrightness = 0.18
    static let saturationMultiplier = 0.80
    static let maximumSaturation = 0.60
    static let neutralSaturation = 0.08
    static let unrepresentativeVariance = 0.07
    static let minimumDominantShare = 0.35
    static let saturationCancellationRatio = 0.55
    static let textMinimumScale: CGFloat = 0.80
    static let referenceScreenWidth: CGFloat = 390
    static let secondarySymbolFraction: CGFloat = 0.05
    static let heartReferenceSize: CGFloat = 25
    static let heartIconScale: CGFloat = 0.75
    static let heartSymbolFraction = heartReferenceSize * heartIconScale / referenceScreenWidth
    static let inactiveSymbolOpacity = 0.50
    static let outputSymbolFraction: CGFloat = 0.025
    static let outputReferenceTextSize: CGFloat = 10
    static let outputTextScale: CGFloat = 0.88
    static let outputTextFraction = outputReferenceTextSize * outputTextScale / referenceScreenWidth
    static let transportIconFraction: CGFloat = 0.43
    static let innerTransportIconScale: CGFloat = 0.80
}

struct PlayerArtworkPalette: Equatable, Sendable {
    let source: UInt32
    let top: UInt32
    let bottom: UInt32
    let topLuminance: Double
    var darkStatusText: Bool { topLuminance > PlayerReferenceStyle.darkStatusThreshold }
    static let missing = Self(source: 0xFF000000, topLuminance: 0)

    init(source: UInt32, topLuminance: Double) {
        self.source = source
        self.topLuminance = topLuminance
        let hsv = Self.hsv(source)
        let saturation = hsv.s < PlayerReferenceStyle.neutralSaturation ? 0
            : min(hsv.s * PlayerReferenceStyle.saturationMultiplier, PlayerReferenceStyle.maximumSaturation)
        let brightness = min(max(hsv.v * PlayerReferenceStyle.brightnessMultiplier,
                                 PlayerReferenceStyle.minimumBrightness), PlayerReferenceStyle.maximumBrightness)
        // Very dark covers stay above pure black. Their lower end
        // never becomes brighter merely to reach the normal 0.12–0.18 range.
        let lower = min(brightness, max(PlayerReferenceStyle.minimumBrightness,
            min(PlayerReferenceStyle.maximumBottomBrightness,
                max(PlayerReferenceStyle.minimumBottomBrightness, brightness * PlayerReferenceStyle.bottomBrightnessMultiplier))))
        top = Self.rgb(h: hsv.h, s: saturation, v: brightness)
        bottom = Self.rgb(h: hsv.h, s: saturation, v: lower)
    }

    static func fromPixels(_ pixels: [UInt32], width: Int, height: Int, dominant: UInt32? = nil) -> Self {
        guard width > 0, height > 0, pixels.count == width * height else { return .missing }
        let topRows = max(1, Int(ceil(Double(height) * PlayerReferenceStyle.topSampleFraction)))
        let bottomRows = max(1, Int(ceil(Double(height) * PlayerReferenceStyle.bottomSampleFraction)))
        let upper = Array(pixels.prefix(topRows * width)).filter { $0 >> 24 >= 128 }
        let lower = Array(pixels.suffix(bottomRows * width)).filter { $0 >> 24 >= 128 }
        guard !lower.isEmpty else { return .missing }
        let average = mean(lower)
        let averageSaturation = lower.map { hsv($0).s }.reduce(0, +) / Double(lower.count)
        let components = channels(average)
        var summedVariance = 0.0
        for pixel in lower {
            let p = channels(pixel)
            let redDelta = p.r - components.r
            let greenDelta = p.g - components.g
            let blueDelta = p.b - components.b
            summedVariance += (redDelta * redDelta + greenDelta * greenDelta + blueDelta * blueDelta) / 3
        }
        let variance = summedVariance / Double(lower.count)
        let distribution = dominantColour(lower)
        let cancelledHue = hsv(average).s < averageSaturation * PlayerReferenceStyle.saturationCancellationRatio
        let unrepresentative = averageSaturation >= PlayerReferenceStyle.neutralSaturation
            && variance > PlayerReferenceStyle.unrepresentativeVariance
            && (cancelledHue || distribution.share < PlayerReferenceStyle.minimumDominantShare)
        let source = unrepresentative ? (dominant ?? dominantColour(pixels).colour) : average
        let luminance = upper.isEmpty ? 0 : upper.map(relativeLuminance).reduce(0, +) / Double(upper.count)
        return Self(source: source, topLuminance: luminance)
    }

    static func channels(_ value: UInt32) -> (r: Double, g: Double, b: Double) {
        (Double((value >> 16) & 255) / 255, Double((value >> 8) & 255) / 255, Double(value & 255) / 255)
    }

    static func relativeLuminance(_ value: UInt32) -> Double {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let c = channels(value)
        return 0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b)
    }

    static func hsv(_ value: UInt32) -> (h: Double, s: Double, v: Double) {
        let c = channels(value), highest = max(c.r, c.g, c.b), lowest = min(c.r, c.g, c.b)
        let delta = highest - lowest
        guard delta > 0, highest > 0 else { return (0, 0, highest) }
        let hue = highest == c.r ? (c.g - c.b) / delta
            : highest == c.g ? 2 + (c.b - c.r) / delta : 4 + (c.r - c.g) / delta
        return ((hue / 6 + 1).truncatingRemainder(dividingBy: 1), delta / highest, highest)
    }

    private static func rgb(h: Double, s: Double, v: Double) -> UInt32 {
        let c = v * s, sector = h * 6
        let x = c * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1)), m = v - c
        let rgb: (Double, Double, Double)
        switch Int(sector) % 6 {
        case 0: rgb = (c, x, 0)
        case 1: rgb = (x, c, 0)
        case 2: rgb = (0, c, x)
        case 3: rgb = (0, x, c)
        case 4: rgb = (x, 0, c)
        default: rgb = (c, 0, x)
        }
        return argb(rgb.0 + m, rgb.1 + m, rgb.2 + m)
    }

    private static func argb(_ r: Double, _ g: Double, _ b: Double) -> UInt32 {
        func byte(_ c: Double) -> UInt32 { UInt32((min(max(c, 0), 1) * 255).rounded()) }
        return 0xFF000000 | (byte(r) << 16) | (byte(g) << 8) | byte(b)
    }

    private static func mean(_ pixels: [UInt32]) -> UInt32 {
        guard !pixels.isEmpty else { return 0xFF000000 }
        let sum = pixels.reduce((r: 0.0, g: 0.0, b: 0.0)) { result, pixel in
            let c = channels(pixel)
            return (result.r + c.r, result.g + c.g, result.b + c.b)
        }
        return argb(sum.r / Double(pixels.count), sum.g / Double(pixels.count), sum.b / Double(pixels.count))
    }

    static func dominantColour(_ pixels: [UInt32]) -> (colour: UInt32, share: Double) {
        var buckets: [UInt32: [UInt32]] = [:]
        for p in pixels where p >> 24 >= 128 {
            let red = (p >> 20) & 15
            let green = (p >> 12) & 15
            let blue = (p >> 4) & 15
            let key = (red << 8) | (green << 4) | blue
            buckets[key, default: []].append(p)
        }
        guard let key = buckets.keys.sorted().max(by: { buckets[$0]!.count < buckets[$1]!.count }),
              let values = buckets[key] else { return (0xFF000000, 0) }
        return (mean(values), Double(values.count) / Double(max(pixels.count, 1)))
    }
}

actor PlayerArtworkPaletteCache {
    static let shared = PlayerArtworkPaletteCache()
    private var values: [String: PlayerArtworkPalette] = [:]
    private var order: [String] = []
    private static let capacity = 120
    private static let sampleWidth = 64

    func palette(for url: URL, image: UIImage?, revision: Int, aspect: Double) -> PlayerArtworkPalette {
        guard aspect.isFinite, aspect > 0 else { return .missing }
        let key = "\(url.path)|\(revision)|\(Int((aspect * 10_000).rounded()))"
        if let value = values[key] { return value }
        guard let cg = image?.cgImage, let value = Self.sample(cg, aspect: aspect) else { return .missing }
        values[key] = value
        order.append(key)
        while order.count > Self.capacity { values.removeValue(forKey: order.removeFirst()) }
        return value
    }

    static func sample(_ image: CGImage, aspect: Double) -> PlayerArtworkPalette? {
        guard aspect.isFinite, aspect > 0 else { return nil }
        let width = Double(image.width), height = Double(image.height)
        let cropWidth = min(width, height * aspect), cropHeight = min(height, width / aspect)
        let crop = CGRect(x: (width - cropWidth) / 2, y: (height - cropHeight) / 2,
                          width: cropWidth, height: cropHeight).integral
        guard let visible = image.cropping(to: crop),
              let full = raster(image, width: sampleWidth, height: sampleWidth) else { return nil }
        let rows = min(max(Int((Double(sampleWidth) / aspect).rounded()), 8), 256)
        guard let pixels = raster(visible, width: sampleWidth, height: rows) else { return nil }
        return .fromPixels(pixels, width: sampleWidth, height: rows, dominant: PlayerArtworkPalette.dominantColour(full).colour)
    }

    private static func raster(_ image: CGImage, width: Int, height: Int) -> [UInt32]? {
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = rgba.withUnsafeMutableBytes { buffer -> Bool in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                    bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        return stride(from: 0, to: rgba.count, by: 4).map { i in
            let alpha = UInt32(rgba[i + 3])
            guard alpha > 0 else { return 0 }
            func unpremultiply(_ c: UInt8) -> UInt32 { min(UInt32(c) * 255 / alpha, 255) }
            let red = unpremultiply(rgba[i])
            let green = unpremultiply(rgba[i + 1])
            let blue = unpremultiply(rgba[i + 2])
            let colour = (red << 16) | (green << 8) | blue
            return (alpha << 24) | colour
        }
    }
}

struct PlayerStatusBarPreference: PreferenceKey {
    static var defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = nextValue() }
}

struct PlayerSystemAppearancePreference: PreferenceKey {
    static var defaultValue: ColorScheme? = nil
    static func reduce(value: inout ColorScheme?, nextValue: () -> ColorScheme?) { value = nextValue() ?? value }
}

/// The scene-level preference wins over the app's theme preference. Preserve the
/// content theme while changing the system status style, including during dismissal.
struct PlayerStatusBarRootAppearance: ViewModifier {
    let applicationScheme: ColorScheme?
    @Environment(\.colorScheme) private var ambientScheme
    @State private var statusScheme: ColorScheme?
    @State private var preservedScheme: ColorScheme?

    func body(content: Content) -> some View {
        content
            .environment(\.colorScheme, applicationScheme ?? preservedScheme ?? ambientScheme)
            .preferredColorScheme(statusScheme ?? applicationScheme)
            .onPreferenceChange(PlayerSystemAppearancePreference.self) { next in
                if statusScheme == nil, next != nil { preservedScheme = applicationScheme ?? ambientScheme }
                statusScheme = next
            }
            .onChange(of: ambientScheme) { _, _ in
                if statusScheme == nil { preservedScheme = nil }
            }
    }
}

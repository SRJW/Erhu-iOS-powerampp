import SwiftUI
import UIKit
import Observation
import XCTest
@testable import Erhu

final class PlayerArtworkPaletteTests: XCTestCase {
    func testBackgroundLimitsPreserveWhiteContrastAcrossTheRGBGamut() {
        for r in stride(from: 0, through: 255, by: 17) {
            for g in stride(from: 0, through: 255, by: 17) {
                for b in stride(from: 0, through: 255, by: 17) {
                    let source = UInt32(0xFF000000) | UInt32(r) << 16 | UInt32(g) << 8 | UInt32(b)
                    let palette = PlayerArtworkPalette(source: source, topLuminance: 0)
                    for colour in [palette.top, palette.bottom] {
                        let hsv = PlayerArtworkPalette.hsv(colour)
                        XCTAssertGreaterThanOrEqual(1.05 / (PlayerArtworkPalette.relativeLuminance(colour) + 0.05), 4.5)
                        XCTAssertLessThanOrEqual(hsv.s, PlayerReferenceStyle.maximumSaturation + 1e-12)
                        XCTAssertLessThanOrEqual(hsv.v, PlayerReferenceStyle.maximumBrightness + 0.004)
                        XCTAssertGreaterThanOrEqual(hsv.v, PlayerReferenceStyle.minimumBrightness - 0.004)
                    }
                    XCTAssertLessThanOrEqual(PlayerArtworkPalette.hsv(palette.bottom).v,
                                             PlayerArtworkPalette.hsv(palette.top).v)
                    if PlayerArtworkPalette.hsv(source).s < PlayerReferenceStyle.neutralSaturation {
                        let c = PlayerArtworkPalette.channels(palette.top)
                        XCTAssertEqual(c.r, c.g)
                        XCTAssertEqual(c.g, c.b)
                    }
                }
            }
        }
    }

    func testExtractionUsesTopAndBottomBandsInsteadOfTheWholeImageAverage() {
        let width = 100, height = 100
        var pixels = [UInt32](repeating: 0xFF0000FF, count: width * height)
        for y in 0..<8 { for x in 0..<width { pixels[y * width + x] = 0xFFFFFFFF } }
        for y in 85..<100 { for x in 0..<width { pixels[y * width + x] = 0xFF777777 } }
        let palette = PlayerArtworkPalette.fromPixels(pixels, width: width, height: height)
        XCTAssertEqual(palette.source, 0xFF777777, "A neutral bottom border must remain neutral even over a blue image")
        XCTAssertTrue(palette.darkStatusText)
        XCTAssertEqual(palette.topLuminance, 1, accuracy: 0.001)
        let c = PlayerArtworkPalette.channels(palette.top)
        XCTAssertEqual(c.r, c.g)
        XCTAssertEqual(c.g, c.b)
    }

    func testAnUnrepresentativeMixedBandUsesTheActualDominantColour() {
        let width = 100, height = 100
        var pixels = [UInt32](repeating: 0xFF0000FF, count: width * height)
        for y in 85..<100 {
            for x in 0..<width { pixels[y * width + x] = x % 2 == 0 ? 0xFFFF0000 : 0xFF00FFFF }
        }
        let palette = PlayerArtworkPalette.fromPixels(pixels, width: width, height: height)
        XCTAssertEqual(palette.source, 0xFF0000FF, "Complementary colours must not invent a grey average when the band is unrepresentative")
    }

    @MainActor
    func testFiveCoverFamiliesAreReadableAndHaveNoBottomSeam() throws {
        let size = CGSize(width: 200, height: 500)
        let fixtures = ["white-with-text", "almost-black", "greyscale", "saturated-red", "multicolour"]
        for name in fixtures {
            let image = fixture(name)
            let palette = try XCTUnwrap(PlayerArtworkPaletteCache.sample(try XCTUnwrap(image.cgImage),
                aspect: Double(size.width / (size.height * PlayerReferenceStyle.coverHeightFraction))))
            XCTAssertEqual(palette.darkStatusText, name == "white-with-text", name)
            let background = PlayerFullBleedBackground(palette: palette) {
                Image(uiImage: image).resizable().scaledToFill()
            }
            let rendered = try render(background, size: size)
            let attachment = XCTAttachment(image: rendered)
            attachment.name = "Player background — " + name
            attachment.lifetime = .keepAlways
            add(attachment)
            let pixels = try rgba(rendered)
            for y in [300, 340, 400, 480] {
                let c = colour(pixels, x: 100, y: y, width: 200)
                let argb = UInt32(0xFF000000) | UInt32(c[0]) << 16 | UInt32(c[1]) << 8 | UInt32(c[2])
                XCTAssertGreaterThanOrEqual(1.05 / (PlayerArtworkPalette.relativeLuminance(argb) + 0.05), 4.5, name)
            }
            let above = colour(pixels, x: 100, y: 284, width: 200)
            let below = colour(pixels, x: 100, y: 286, width: 200)
            for channel in 0..<3 {
                XCTAssertLessThan(abs(Double(above[channel]) - Double(below[channel])) / 255, 0.04,
                                  "A seam appeared at the cover boundary: " + name)
            }
        }
    }

    @MainActor
    func testFixedCoverHeightAndStatusScrimHeight() throws {
        let background = PlayerFullBleedBackground(palette: .missing) { Color.white }
        let pixels = try rgba(render(background, size: CGSize(width: 200, height: 500)))
        func red(_ y: Int) -> Double { Double(colour(pixels, x: 100, y: y, width: 200)[0]) / 255 }
        XCTAssertGreaterThan(red(120), red(100) + 0.02, "The scrim must still fade at 100 pt and end at 115 pt")
        XCTAssertGreaterThan(red(200), 0.98)
        XCTAssertGreaterThan(red(270), 0.22, "The cover must reach 57% rather than ending at 55%")
        XCTAssertEqual(red(286), Double(PlayerArtworkPalette.missing.top & 255) / 255, accuracy: 0.025)
    }

    @MainActor
    func testCoverCompositionHasNoZoomOrTranslationDuringTrackChanges() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100)).image { context in
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 2, height: 100))
            UIColor.green.setFill(); context.fill(CGRect(x: 98, y: 0, width: 2, height: 100))
        }
        let size = CGSize(width: 200, height: 200)
        for amount in [0.0, 0.5, 1.0] {
            for direction in [-1, 1] {
                let view = ArtworkSlideLayer(progress: amount, direction: direction, incoming: false, reduceMotion: false, size: size) {
                    Image(uiImage: image).resizable().scaledToFill()
                }
                let pixels = try rgba(render(view, size: size))
                let left = colour(pixels, x: 1, y: 100, width: 200)
                let right = colour(pixels, x: 198, y: 100, width: 200)
                XCTAssertGreaterThan(left[0], 200, "The source's left edge must not be zoomed away")
                XCTAssertGreaterThan(right[1], 200, "The source's right edge must not be zoomed away")
            }
        }
    }

    @MainActor
    func testCroppingSamplesTheVisibleTopOfPortraitArtwork() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 200)).image { context in
            UIColor.black.setFill(); context.fill(CGRect(x: 0, y: 0, width: 100, height: 200))
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 50, width: 100, height: 10))
        }
        let palette = try XCTUnwrap(PlayerArtworkPaletteCache.sample(try XCTUnwrap(image.cgImage), aspect: 1))
        XCTAssertTrue(palette.darkStatusText, "The displayed crop starts at source y=50, not at the hidden black source edge")
    }

    @MainActor
    func testPaletteCacheSeparatesArtworkRevisionsAndVisibleAspectRatios() async throws {
        let cache = PlayerArtworkPaletteCache()
        let url = URL(fileURLWithPath: "/synthetic-player-cover.mp3")
        let first = await cache.palette(for: url, image: fixture("white-with-text"), revision: 0, aspect: 1)
        let reused = await cache.palette(for: url, image: fixture("almost-black"), revision: 0, aspect: 1)
        XCTAssertEqual(reused, first, "Repeated renders must use the cached result")
        let updated = await cache.palette(for: url, image: fixture("almost-black"), revision: 1, aspect: 1)
        XCTAssertNotEqual(updated, first, "Changing artwork must invalidate the cache")
        let resized = await cache.palette(for: url, image: fixture("white-with-text"), revision: 1, aspect: 0.8)
        XCTAssertNotEqual(resized, updated, "A new visible crop needs its own sampled bands")
    }

    @MainActor
    func testStatusTextFollowsTheVisibleCoverDuringADissolve() {
        var layer = ArtworkSlideLayer(progress: 0, direction: 1, incoming: true, reduceMotion: false,
            size: CGSize(width: 200, height: 200), outgoingLuminance: 1, incomingLuminance: 0) { Color.clear }
        XCTAssertTrue(layer.usesDarkStatusText)
        layer.animatableData = 0.5
        XCTAssertFalse(layer.usesDarkStatusText)
        layer.animatableData = 1
        XCTAssertFalse(layer.usesDarkStatusText)
    }

    @MainActor
    func testStatusStyleCanChangeWithoutChangingTheContentTheme() async throws {
        let previous = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)
        let scene = try XCTUnwrap(previous?.windowScene ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let probe = AppearanceProbe()
        let controller = UIHostingController(rootView: AppearanceContent(probe: probe)
            .modifier(PlayerStatusBarRootAppearance(applicationScheme: .dark)))
        let window = UIWindow(windowScene: scene)
        window.frame = scene.screen.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        window.layoutIfNeeded()
        @MainActor func waitFor(_ condition: () -> Bool) async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(16)) }
            XCTAssertTrue(condition())
        }
        try await waitFor { probe.contentScheme == .dark && controller.view.traitCollection.userInterfaceStyle == .dark }
        probe.systemScheme = .light
        try await waitFor { probe.contentScheme == .dark && controller.view.traitCollection.userInterfaceStyle == .light }
        probe.systemScheme = nil
        try await waitFor { probe.contentScheme == .dark && controller.view.traitCollection.userInterfaceStyle == .dark }
    }

    @MainActor @Observable final class AppearanceProbe {
        var systemScheme: ColorScheme?
        var contentScheme: ColorScheme?
    }

    private struct AppearanceContent: View {
        let probe: AppearanceProbe
        @Environment(\.colorScheme) private var scheme
        var body: some View {
            Color.clear
                .preference(key: PlayerSystemAppearancePreference.self, value: probe.systemScheme)
                .onAppear { probe.contentScheme = scheme }
                .onChange(of: scheme) { _, value in probe.contentScheme = value }
        }
    }

    @MainActor
    private func fixture(_ name: String) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 300, height: 300)).image { context in
            let colour: UIColor
            switch name {
            case "almost-black": colour = UIColor(white: 0.015, alpha: 1)
            case "greyscale": colour = UIColor(white: 0.55, alpha: 1)
            case "saturated-red": colour = UIColor(red: 1, green: 0, blue: 0, alpha: 1)
            default: colour = UIColor(red: 0.15, green: 0.65, blue: 0.8, alpha: 1)
            }
            colour.setFill(); context.fill(CGRect(x: 0, y: 0, width: 300, height: 300))
            if name == "white-with-text" {
                UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 300, height: 36))
                for y in stride(from: 60, through: 240, by: 24) {
                    ("ALBUM TITLE / ARTIST / WORDS" as NSString).draw(at: CGPoint(x: 8, y: CGFloat(y)),
                        withAttributes: [.font: UIFont.boldSystemFont(ofSize: 14), .foregroundColor: UIColor.black])
                }
            } else if name == "multicolour" {
                for (index, colour) in [UIColor.red, .green, .blue, .yellow, .magenta, .cyan].enumerated() {
                    colour.setFill(); context.fill(CGRect(x: CGFloat(index * 50), y: 0, width: 50, height: 300))
                }
            }
        }
    }

    @MainActor
    private func render<Content: View>(_ view: Content, size: CGSize) throws -> UIImage {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 1
        return try XCTUnwrap(renderer.uiImage)
    }

    private func rgba(_ image: UIImage) throws -> [UInt8] {
        let cg = try XCTUnwrap(image.cgImage)
        var bytes = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: cg.width, height: cg.height,
                bitsPerComponent: 8, bytesPerRow: cg.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        }
        return bytes
    }

    private func colour(_ bytes: [UInt8], x: Int, y: Int, width: Int) -> [UInt8] {
        let start = (y * width + x) * 4
        return Array(bytes[start..<start + 3])
    }
}

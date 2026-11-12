import SwiftUI
import UIKit
import Observation
import XCTest
@testable import Erhu

/// Render the production containers, rather than accepting a mathematically correct frame
/// while its pixels are clipped, covered by a sibling, or collapsed to a tiny ideal size.
final class PlayerRenderingTests: XCTestCase {
    @MainActor
    func testFullBleedCoverCropsEdgesAndDissolvesIntoMutedBackground() async throws {
        let url = TagFixtures.write(TagFixtures.mp3(v4: true), name: "player-cover-composition.mp3")
        defer { try? FileManager.default.removeItem(at: url) }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100)).image { context in
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 10, height: 100))
            UIColor.green.setFill(); context.fill(CGRect(x: 90, y: 0, width: 10, height: 100))
        }
        var edit = TagWriteRequest()
        edit.artwork = try XCTUnwrap(image.pngData())
        try TagWriter.write(edit, to: url)
        ArtworkLoader.shared.forget(path: url.path)
        _ = await ArtworkLoader.shared.image(for: url, maxPixels: 600)
        let backdrop = PlayerFullBleedBackground(dominant: Color(.sRGB, red: 0, green: 0, blue: 1)) {
            SongArtworkView(url: url, maxPixels: 1200, contentMode: .fill).scaleEffect(1.10)
        }
        let rendered = try pixels(backdrop, size: CGSize(width: 200, height: 500))
        // The 55%-height fill crop plus zoom removes the source's side stripes.
        // Its visible image reaches both screen edges, without a card border.
        assertColor(rendered, at: CGPoint(x: 8, y: 60), dominant: 2)
        assertColor(rendered, at: CGPoint(x: 192, y: 60), dominant: 2)
        assertColor(rendered, at: CGPoint(x: 100, y: 60), dominant: 2)
        XCTAssertLessThan(rendered.color(x: 100, y: 10)[2], rendered.color(x: 100, y: 60)[2],
                          "The upper scrim must darken the image behind system status text")
        let belowCover = rendered.color(x: 100, y: 300)
        let bottom = rendered.color(x: 100, y: 480)
        XCTAssertGreaterThan(belowCover[2], belowCover[0], "The muted background must retain the artwork hue")
        XCTAssertGreaterThan(belowCover[0], 0.02, "Desaturation introduces neutral channels; the background is not pure blue")
        XCTAssertLessThan(bottom.max() ?? 1, belowCover.max() ?? 0, "The background darkens towards the home indicator")
        XCTAssertLessThan(bottom.max() ?? 1, 0.30)

    }

    @MainActor
    func testCoverBackgroundActuallyBlendsBothArtworkColours() throws {
        var previousRed = 2.0
        var previousBlue = -1.0
        var endpoints: [[Double]] = []
        for amount in [0.0, 0.25, 0.5, 0.75, 1.0] {
            let view = PlayerFullBleedBackground(dominant: .red, secondaryDominant: .blue, blend: amount) { Color.clear }
            let rendered = try pixels(view, size: CGSize(width: 200, height: 500))
            let sample = rendered.color(x: 100, y: 300)
            XCTAssertLessThanOrEqual(sample[0], previousRed + 0.02, "The old cover colour must fade: \(sample)")
            XCTAssertGreaterThanOrEqual(sample[2], previousBlue - 0.02, "The next cover colour must enter: \(sample)")
            previousRed = sample[0]; previousBlue = sample[2]
            endpoints.append(sample)
        }
        XCTAssertGreaterThan(endpoints[0][0] - endpoints[4][0], 0.10)
        XCTAssertGreaterThan(endpoints[4][2] - endpoints[0][2], 0.10)
        XCTAssertGreaterThan(endpoints[2][0], 0.10, "Midpoint must retain the outgoing colour")
        XCTAssertGreaterThan(endpoints[2][2], 0.10, "Midpoint must retain the incoming colour")
    }

    @MainActor
    func testCoverLayersDissolveAtTheSameVisibleProgress() throws {
        let size = CGSize(width: 200, height: 200)
        let mixed = ZStack {
            Color.black
            ArtworkSlideLayer(progress: 0.5, direction: 1, incoming: false, reduceMotion: false, size: size) { Color.red }
            ArtworkSlideLayer(progress: 0.5, direction: 1, incoming: true, reduceMotion: false, size: size) { Color.blue }
        }
        let image = try pixels(mixed, size: size)
        let centre = image.color(x: 100, y: 100)
        XCTAssertGreaterThan(centre[0], 0.20, "The departing cover must remain visible: \(centre)")
        XCTAssertGreaterThan(centre[2], 0.40, "The arriving cover must blend over it: \(centre)")
    }

    @MainActor
    func testChangingCoverRendersAnIntermediateColourFrame() async throws {
        let folder = LibraryPaths.musicFolder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let names = ["blend-red-\(UUID().uuidString).mp3", "blend-blue-\(UUID().uuidString).mp3"]
        let urls = names.map { folder.appendingPathComponent($0) }
        defer { for url in urls { try? FileManager.default.removeItem(at: url) } }
        for (index, url) in urls.enumerated() {
            try TagFixtures.mp3(v4: true).write(to: url)
            let image = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32)).image { context in
                (index == 0 ? UIColor.red : UIColor.blue).setFill()
                context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
            }
            var request = TagWriteRequest()
            request.artwork = try XCTUnwrap(image.pngData())
            try TagWriter.write(request, to: url)
            ArtworkLoader.shared.forget(path: url.path)
            _ = await ArtworkLoader.shared.image(for: url, maxPixels: 1600)
            _ = await LyricsPaletteCache.shared.palette(for: url)
        }
        let songs = names.enumerated().map { Song(id: Int64(-9500 - $0.offset), title: "Cover fixture", artist: "Local", album: "Fixture", durationMs: 120_000, path: $0.element) }
        let selection = CoverRenderSelection(song: songs[0])
        let player = PlayerController(database: try LibraryDatabase.inMemory(), transitions: TransitionSettingsStore())
        let previous = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
        let size = CGSize(width: 200, height: 500)
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        let controller = UIHostingController(rootView: CoverRenderHost(selection: selection).environment(player).environment(\.playerReduceMotion, false))
        controller.safeAreaRegions = []
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        window.layoutIfNeeded(); controller.view.layoutIfNeeded()
        func sample() throws -> [Double] {
            let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
            let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                controller.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.lifetime = .keepAlways
            add(attachment)
            return try rgbaPixels(XCTUnwrap(image.cgImage)).color(x: 100, y: 300)
        }
        try await Task.sleep(for: .milliseconds(250))
        let first = try sample()
        selection.song = songs[1]
        try await Task.sleep(for: .milliseconds(220))
        let middle = try sample()
        try await Task.sleep(for: .milliseconds(700))
        let last = try sample()
        XCTAssertGreaterThan(first[0] - last[0], 0.10, "Red cover must change to blue: \(first) -> \(last)")
        XCTAssertGreaterThan(middle[2], first[2] + 0.02, "The actual animation must show blue before settling: \(first), \(middle), \(last)")
        XCTAssertGreaterThan(middle[0], last[0] + 0.02, "The actual animation must retain red at an intermediate frame: \(first), \(middle), \(last)")
    }

    @MainActor @Observable private final class CoverRenderSelection {
        var song: Song
        init(song: Song) { self.song = song }
    }
    private struct CoverRenderHost: View {
        let selection: CoverRenderSelection
        var body: some View { ReferencePlayerBackdrop(song: selection.song, artworkDrag: .constant(0)) }
    }

    func testPlayerDominantColourIsNotReplacedByTheDarkLyricsSurface() {
        let original: UInt32 = 0xFF56_887F
        let pixels = Array(repeating: original, count: 900) + Array(repeating: UInt32(0xFFFF_FFFF), count: 124)
        let palette = LyricsPalette.fromPixels(pixels)
        XCTAssertEqual(palette.artworkDominant, original)
        XCTAssertNotEqual(palette.surface, original)
        XCTAssertEqual(palette.forScheme(.light).artworkDominant, original)
        XCTAssertEqual(palette.forScheme(.dark).artworkDominant, original)
    }

    @MainActor
    func testCachedArtworkIsVisibleOnTheFirstFrameWithoutWaitingForATask() async throws {
        let url = TagFixtures.write(TagFixtures.mp3(v4: true), name: "first-frame-cover.mp3")
        defer { try? FileManager.default.removeItem(at: url) }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        }
        var edit = TagWriteRequest()
        edit.artwork = try XCTUnwrap(image.pngData())
        try TagWriter.write(edit, to: url)
        ArtworkLoader.shared.forget(path: url.path)
        _ = await ArtworkLoader.shared.image(for: url, maxPixels: 600)
        // ImageRenderer does not run .task: this must use the existing 600px cache immediately,
        // even though the full player requests 1200px artwork.
        let rendered = try pixels(SongArtworkView(url: url, maxPixels: 1200), size: CGSize(width: 100, height: 100))
        assertColor(rendered, at: CGPoint(x: 50, y: 50), dominant: 0)
    }

    @MainActor
    func testCarouselActuallyPaintsBothPreviewsAndTheNearestCover() throws {
        let entries = (0..<4).map { QueueEntry(song: testSong(Int64($0 + 1))) }
        var scene = CarouselScene()
        scene.select(CarouselSelection(previous: entries[0], current: entries[1], next: entries[2]))
        let colors = [entries[0].id: Color.red, entries[1].id: .green, entries[2].id: .blue, entries[3].id: .red]
        func strip(_ focus: CGFloat, front: Int) -> some View {
            CarouselStrip(items: scene.items, focus: focus, frontOrdinal: front, stack: 0,
                          viewport: CGSize(width: 390, height: 450), cardSize: CGSize(width: 280, height: 380),
                          reduceMotion: false, meter: CarouselPresentationMeter()) { item in
                Rectangle().fill(colors[item.entry.id] ?? .white).frame(width: 280, height: 380)
            }
            .background(Color.black)
        }
        let resting = try pixels(strip(0, front: 0), size: CGSize(width: 390, height: 450))
        assertColor(resting, at: CGPoint(x: 5, y: 225), dominant: 0)
        assertColor(resting, at: CGPoint(x: 195, y: 225), dominant: 1)
        assertColor(resting, at: CGPoint(x: 385, y: 225), dominant: 2)
        let forward = try pixels(strip(0.75, front: 1), size: CGSize(width: 390, height: 450))
        assertColor(forward, at: CGPoint(x: 195, y: 225), dominant: 2)
        let reverse = try pixels(strip(0.25, front: 0), size: CGSize(width: 390, height: 450))
        assertColor(reverse, at: CGPoint(x: 195, y: 225), dominant: 1)
        let midpoint = try pixels(strip(0.5, front: 1), size: CGSize(width: 390, height: 450))
        for x in 192...198 {
            XCTAssertLessThan(midpoint.color(x: x, y: 225).max() ?? 1, 0.05, "The two covers must have a visible gap")
        }
        scene.select(CarouselSelection(previous: entries[1], current: entries[2], next: entries[3]))
        scene.settle()
        let afterSkip = try pixels(strip(1, front: 1), size: CGSize(width: 390, height: 450))
        assertColor(afterSkip, at: CGPoint(x: 5, y: 225), dominant: 1)
        assertColor(afterSkip, at: CGPoint(x: 195, y: 225), dominant: 2)
        assertColor(afterSkip, at: CGPoint(x: 385, y: 225), dominant: 0)
    }

    @MainActor
    func testOpeningChromeIsVisibleDuringTheCoverFlight() throws {
        for progress in [CGFloat(0.35), 0.65, 1] {
            let chrome = Color.green.modifier(PlayerChromeOpacity(progress: progress)).background(Color.black)
            let rendered = try pixels(chrome, size: CGSize(width: 100, height: 100))
            let green = rendered.color(x: 50, y: 50)[1]
            XCTAssertGreaterThan(green, 0.15, "Controls must join the entrance, not wait for its completion")
            if progress < 1 { XCTAssertLessThan(green, 0.95) }
        }
    }

    @MainActor
    func testCollapseShowsOnlyFloatingArtworkOverTheLibrary() throws {
        let drag = PlayerDragState()
        drag.setPresented(true, reduceMotion: false)
        drag.finishEntrance()
        drag.update(drag.travel / 2)
        let source = CGRect(x: 55, y: 100, width: 280, height: 280)
        let mini = CGRect(x: 20, y: 745, width: 44, height: 44)
        let content = ZStack {
            Color.blue // The library, underneath the player.
            Color.green.modifier(PlayerCollapseVisibility()) // Carousel paint and backdrop.
            Color.green.frame(width: 300, height: 90).modifier(PlayerChromeFade()) // Transport chrome.
        }
        .overlay {
            PlayerArtworkOverlay(progress: drag.progress, frames: .init(expanded: source, mini: mini)) { Color.red }
        }
        .environment(drag)
        let rendered = try pixels(content, size: CGSize(width: 390, height: 844))
        assertColor(rendered, at: CGPoint(x: (source.midX + mini.midX) / 2, y: (source.midY + mini.midY) / 2), dominant: 0)
        assertColor(rendered, at: CGPoint(x: 350, y: 422), dominant: 2)
        assertColor(rendered, at: CGPoint(x: 195, y: 100), dominant: 2)
    }

    @MainActor
    func testFirstPartOfPullBlendsPlayerAndLibraryInsteadOfCuttingToHome() throws {
        let drag = PlayerDragState()
        drag.setPresented(true, reduceMotion: true)
        drag.finishEntrance(reduceMotion: true)
        drag.update(PlayerDragState.chromeFadeDistance / 4)
        let view = ZStack {
            Color.blue
            Color(red: 0, green: 1, blue: 0).modifier(PlayerCollapseVisibility())
        }.environment(drag)
        let rendered = try pixels(view, size: CGSize(width: 100, height: 100))
        let color = rendered.color(x: 50, y: 50)
        XCTAssertGreaterThan(color[1], 0.5, "A small pull must retain most of the player")
        XCTAssertGreaterThan(color[2], 0.05, "The library must be revealed continuously underneath")
        drag.beginDismissal(reduceMotion: true)
    }

    @MainActor
    func testDepthTurnoverKeepsItsCompactFootprint() throws {
        let items = (-1...1).map { CarouselScene.Item(ordinal: $0, entry: QueueEntry(song: testSong(Int64($0 + 2)))) }
        for focus in [CGFloat(-0.75), -0.25, 0.25, 0.75] {
            let content = CarouselStrip(items: items, focus: focus, frontOrdinal: Int(focus.rounded()), stack: 1,
                                        viewport: CGSize(width: 390, height: 450), cardSize: CGSize(width: 280, height: 380),
                                        reduceMotion: false, meter: CarouselPresentationMeter()) { _ in
                Color.blue.frame(width: 280, height: 380)
            }.background(Color.black)
            let rendered = try pixels(content, size: CGSize(width: 390, height: 450))
            assertColor(rendered, at: CGPoint(x: 195, y: 225), dominant: 2)
            XCTAssertLessThan(rendered.color(x: 5, y: 225).max() ?? 1, 0.05)
            XCTAssertLessThan(rendered.color(x: 385, y: 225).max() ?? 1, 0.05)
        }
    }

    @MainActor
    func testDepthCardEmergesFromBehindOnTheAppropriateSide() throws {
        for focus in [CGFloat(-0.5), 0.5] {
            // Isolate the exchanging pair: a third rear cover may legitimately fill their gap.
            let items = [0, focus > 0 ? 1 : -1].map {
                CarouselScene.Item(ordinal: $0, entry: QueueEntry(song: testSong(Int64($0 + 2))))
            }
            let content = CarouselStrip(items: items, focus: focus, frontOrdinal: 0, stack: 1,
                                        viewport: CGSize(width: 390, height: 450), cardSize: CGSize(width: 280, height: 380),
                                        reduceMotion: false, meter: CarouselPresentationMeter()) { item in
                Rectangle().fill(item.ordinal == 0 ? Color(red: 0, green: 1, blue: 0) : Color(red: 0, green: 0, blue: 1))
                    .frame(width: 280, height: 380)
            }.background(Color.black)
            let rendered = try pixels(content, size: CGSize(width: 390, height: 450))
            assertColor(rendered, at: CGPoint(x: focus > 0 ? 350 : 40, y: 225), dominant: 2)
            assertColor(rendered, at: CGPoint(x: focus > 0 ? 40 : 350, y: 225), dominant: 1)
            XCTAssertLessThan(rendered.color(x: 195, y: 225).max() ?? 1, 0.05,
                              "The cards' rotated edges must clear each other before exchanging depth")
            let outgoingX = 195 + CarouselPose(distance: -focus, width: 280, stack: 1, reduceMotion: false).x
            let incomingX = 195 + CarouselPose(distance: (focus > 0 ? 1 : -1) - focus, width: 280, stack: 1, reduceMotion: false).x
            XCTAssertGreaterThan(rendered.color(x: Int(outgoingX), y: 225)[1], 0.8, "The outgoing card must stay opaque")
            XCTAssertGreaterThan(rendered.color(x: Int(incomingX), y: 225)[2], 0.8, "The incoming card must stay opaque")
        }
    }

    @MainActor
    func testRestingDepthPreviewPaintsTheActualNeighbourArtwork() throws {
        let items = [0, 1].map { CarouselScene.Item(ordinal: $0, entry: QueueEntry(song: testSong(Int64($0 + 1)))) }
        let view = CarouselStrip(items: items, focus: 0, frontOrdinal: 0, stack: 1,
                                 viewport: CGSize(width: 390, height: 450), cardSize: CGSize(width: 280, height: 380),
                                 reduceMotion: false, meter: CarouselPresentationMeter()) { item in
            Rectangle().fill(item.ordinal == 0 ? Color.green : Color.blue).frame(width: 280, height: 380)
        }.background(Color.black)
        let rendered = try pixels(view, size: CGSize(width: 390, height: 450))
        assertColor(rendered, at: CGPoint(x: 195, y: 28), dominant: 2)
        assertColor(rendered, at: CGPoint(x: 195, y: 225), dominant: 1)
    }

    @MainActor
    func testDepthCleanupDoesNotVisuallySwapCardsAtTheEndOfASlide() throws {
        let items = (-1...1).map { CarouselScene.Item(ordinal: $0, entry: QueueEntry(song: testSong(Int64($0 + 2)))) }
        func strip(focus: CGFloat, anchor: Int) -> some View {
            CarouselStrip(items: items, focus: focus, frontOrdinal: anchor, stack: 1,
                          viewport: CGSize(width: 390, height: 450), cardSize: CGSize(width: 280, height: 380),
                          reduceMotion: false, meter: CarouselPresentationMeter()) { item in
                Rectangle().fill(item.ordinal == 0 ? Color.green : Color.blue).frame(width: 280, height: 380)
            }.background(Color.black)
        }
        for focus in [CGFloat(-1), -0.75, -0.51, 0.51, 0.75, 1] {
            let before = try pixels(strip(focus: focus, anchor: 0), size: CGSize(width: 390, height: 450))
            let after = try pixels(strip(focus: focus, anchor: focus < 0 ? -1 : 1), size: CGSize(width: 390, height: 450))
            XCTAssertTrue(before.bytes == after.bytes, "Settlement must not switch a still-front outgoing cover for its neighbour")
        }
    }

    @MainActor
    func testCoverPixelsEscapeTheScrollViewportAndLandOnTheMiniPlayer() async throws {
        let source = CGRect(x: 55, y: 100, width: 280, height: 280)
        let mini = CGRect(x: 20, y: 745, width: 44, height: 44)
        for progress in [CGFloat(1), 0.5, 0] {
            let content = ZStack(alignment: .topLeading) {
                Color.black
                ScrollView {
                    ZStack(alignment: .topLeading) {
                        Color.gray.frame(width: 280, height: 380).offset(x: 55, y: 100)
                        Color.blue.frame(width: 350, height: 90).offset(x: 20, y: 450)
                    }.frame(width: 390, height: 600, alignment: .topLeading)
                }
                .frame(width: 390, height: 600)
                .clipped()
            }
            .frame(width: 390, height: 844)
            .overlay {
                PlayerArtworkOverlay(progress: progress, frames: PlayerArtworkFrames(expanded: source, mini: mini)) {
                    Color.red
                }
            }
            // ScrollView contains a UIKit-backed scrolling surface. Capture the actual hosted
            // hierarchy, including its controls, rather than ImageRenderer's partial output.
            let rendered = try await windowPixels(content, size: CGSize(width: 390, height: 844))
            let center = CGPoint(x: mini.midX + (source.midX - mini.midX) * progress,
                                 y: mini.midY + (source.midY - mini.midY) * progress)
            assertColor(rendered, at: center, dominant: 0)
            assertColor(rendered, at: CGPoint(x: 350, y: 495), dominant: 2)
        }
    }

    @MainActor
    func testAuditionCursorPaintsOneStraightLineThroughBothWaveforms() throws {
        for fraction in [0.2, 0.5, 0.8] {
            let content = TransitionPlayheadStroke(fraction: fraction).background(Color.black)
            let rendered = try pixels(content, size: CGSize(width: 300, height: 280))
            for y in [15, 70, 140, 210, 265] {
                assertColor(rendered, at: CGPoint(x: fraction * 300, y: Double(y)), dominant: 1)
            }
            let otherX = fraction == 0.5 ? 20 : 150
            let outside = rendered.color(x: otherX, y: 140)
            XCTAssertLessThan(outside.max() ?? 1, 0.05)
        }
    }

    private struct Pixels {
        let bytes: [UInt8]
        let width: Int
        func color(x: Int, y: Int) -> [Double] {
            let start = (y * width + x) * 4
            return (0..<3).map { Double(bytes[start + $0]) / 255 }
        }
    }

    @MainActor
    private func pixels<Content: View>(_ content: Content, size: CGSize) throws -> Pixels {
        let renderer = ImageRenderer(content: content.frame(width: size.width, height: size.height))
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage)
        return try rgbaPixels(image)
    }

    @MainActor
    private func windowPixels<Content: View>(_ content: Content, size: CGSize) async throws -> Pixels {
        let previous = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        let controller = UIHostingController(rootView: content.ignoresSafeArea())
        controller.safeAreaRegions = []
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }
        window.layoutIfNeeded()
        controller.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(controller.view.bounds.size, size)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        var captured = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            captured = controller.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
        }
        XCTAssertTrue(captured, "The hosted scroll view must be captured before inspecting its pixels")
        return try rgbaPixels(XCTUnwrap(image.cgImage))
    }

    private func rgbaPixels(_ image: CGImage) throws -> Pixels {
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: width, height: height,
                                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                                space: CGColorSpaceCreateDeviceRGB(),
                                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return Pixels(bytes: bytes, width: width)
    }

    private func assertColor(_ image: Pixels, at point: CGPoint, dominant: Int,
                             file: StaticString = #filePath, line: UInt = #line) {
        let rgb = image.color(x: Int(point.x.rounded()), y: Int(point.y.rounded()))
        XCTAssertGreaterThan(rgb[dominant], 0.25, "Missing cover/cursor at \(point): \(rgb)", file: file, line: line)
        for component in 0..<3 where component != dominant {
            XCTAssertGreaterThan(rgb[dominant], rgb[component] * 1.4, "Incorrect stacking at \(point): \(rgb)", file: file, line: line)
        }
    }
}

import XCTest
import SwiftUI
import UIKit
@testable import Erhu

final class LibraryChromeTests: XCTestCase {
    @MainActor
    func testTabsOpenTheirRootsInsteadOfRestoringTools() {
        let router = AppRouter()
        router.open(.settings)
        router.select(.equalizer)
        router.open(.artworkFetcher)
        router.select(.library)
        XCTAssertEqual(router.section, .library)
        XCTAssertTrue(router.paths[.library]!.isEmpty)
        router.select(.equalizer)
        XCTAssertTrue(router.paths[.equalizer]!.isEmpty)
    }

    @MainActor
    func testRepeatedTabTapsRequestScrollToTopForEverySection() {
        let router = AppRouter()
        for section in LibrarySection.allCases {
            router.select(section)
            let before = router.scrollToTopRequests[section, default: 0]
            router.select(section)
            router.select(section)
            XCTAssertEqual(router.scrollToTopRequests[section], before + 2)
            XCTAssertTrue(router.paths[section]!.isEmpty)
        }
    }

    @MainActor
    func testReselectingATabActuallyScrollsItsMountedRootToTheTop() async throws {
        let router = AppRouter()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 350, height: 600)
        let host = UIHostingController(rootView: LibraryRootScrollView {
            LazyVStack { ForEach(0..<100) { Text("Track \($0)").frame(height: 44) } }
        }.environment(router).environment(\.artworkSection, .library))
        window.rootViewController = host
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }

        func scrollView(_ view: UIView) -> UIScrollView? {
            if let scroll = view as? UIScrollView { return scroll }
            return view.subviews.lazy.compactMap { scrollView($0) }.first
        }
        for _ in 0..<150 {
            if let scroll = scrollView(host.view), scroll.contentSize.height > 2_000 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let scroll = try XCTUnwrap(scrollView(host.view))
        scroll.setContentOffset(CGPoint(x: 0, y: 800), animated: false)
        XCTAssertGreaterThan(scroll.contentOffset.y, 500)
        router.select(.library)
        for _ in 0..<150 {
            if scroll.contentOffset.y + scroll.adjustedContentInset.top < 1 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertLessThan(scroll.contentOffset.y + scroll.adjustedContentInset.top, 1)
    }

    @MainActor
    func testScrollingCompactsAndReversingScrollExpandsWithoutOvershooting() {
        let chrome = LibraryChromeState()
        chrome.consume(60)
        XCTAssertEqual(chrome.fraction, 0.5)
        chrome.consume(1_000)
        XCTAssertEqual(chrome.fraction, 1)
        chrome.consume(-30)
        XCTAssertEqual(chrome.fraction, 0.75)
        chrome.settle(reduceMotion: true)
        XCTAssertEqual(chrome.fraction, 1)
        chrome.consume(-90)
        chrome.settle(reduceMotion: true)
        XCTAssertEqual(chrome.fraction, 0)
        chrome.consume(.infinity)
        chrome.consume(.nan)
        XCTAssertEqual(chrome.fraction, 0)
        chrome.consume(120)
        chrome.expand(reduceMotion: true)
        XCTAssertEqual(chrome.fraction, 0)
    }

    func testPowerAndThermalRestrictionsSuspendDecorativeWork() {
        for state in [ProcessInfo.ThermalState.nominal, .fair, .serious, .critical] {
            let restricted = VisualWorkBudget(lowPower: true, thermalState: state)
            XCTAssertFalse(restricted.allowsDecorativeMotion)
            XCTAssertEqual(restricted.visualizerInterval, 1.0 / 20)
            let normal = VisualWorkBudget(lowPower: false, thermalState: state)
            XCTAssertEqual(normal.allowsDecorativeMotion, state == .nominal || state == .fair)
        }
    }
}

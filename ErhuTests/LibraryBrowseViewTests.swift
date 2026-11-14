import XCTest
import SwiftUI
import UIKit
import Observation
@testable import Erhu

final class LibraryBrowseViewTests: XCTestCase {
    @MainActor
    func testAllFiveSectionsCanHideAndRevealSearchEvenWithoutResults() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 350, height: 600)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        func verticalScroll(_ view: UIView) -> UIScrollView? {
            if let scroll = view as? UIScrollView { return scroll }
            return view.subviews.lazy.compactMap { verticalScroll($0) }.first
        }
        for title in ["Albums", "Songs", "Artists", "Playlists", "Favorites"] {
            let search = SearchState()
            let router = AppRouter()
            let host = UIHostingController(rootView: NavigationStack {
                LibraryBrowseScrollView(title: title, isTabRoot: title == "Albums",
                                        showsControls: title == "Albums" || title == "Songs",
                                        query: Binding(get: { search.query }, set: { search.query = $0 }),
                                        showsSearch: Binding(get: { search.revealed }, set: { search.revealed = $0 })) {
                    Text("Sort")
                } content: { EmptyView() }
            }.environment(router).environment(LibraryChromeState()).environment(\.artworkSection, router.section))
            window.rootViewController = host
            window.makeKeyAndVisible(); window.layoutIfNeeded()
            for _ in 0..<100 {
                if let scroll = verticalScroll(host.view), abs(scroll.contentOffset.y + scroll.adjustedContentInset.top - 64) < 1 { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            let scroll = try XCTUnwrap(verticalScroll(host.view), title)
            XCTAssertEqual(scroll.contentOffset.y + scroll.adjustedContentInset.top, 64, accuracy: 1, title)
            XCTAssertFalse(search.revealed, title)
            scroll.setContentOffset(CGPoint(x: 0, y: -scroll.adjustedContentInset.top), animated: false)
            try await Task.sleep(for: .milliseconds(50))
            XCTAssertTrue(search.revealed, title)
            scroll.setContentOffset(CGPoint(x: 0, y: 64 - scroll.adjustedContentInset.top), animated: false)
            try await Task.sleep(for: .milliseconds(50))
            XCTAssertFalse(search.revealed, title)
        }
    }

    @MainActor
    func testPullAtTopRevealsSectionSearchInMountedScrollView() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 350, height: 600)
        let search = SearchState()
        let router = AppRouter()
        router.select(.library)
        let host = UIHostingController(rootView: NavigationStack {
            LibraryBrowseScrollView(title: "Albums", query: Binding(get: { search.query }, set: { search.query = $0 }),
                                    showsSearch: Binding(get: { search.revealed }, set: { search.revealed = $0 })) {
                Text("Sort")
            } content: {
                LazyVStack { ForEach(0..<100) { Text("Album \($0)").frame(height: 44) } }
            }
        }.environment(router).environment(LibraryChromeState()).environment(\.artworkSection, .library))
        window.rootViewController = host
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }

        func verticalScroll(_ view: UIView) -> UIScrollView? {
            if let scroll = view as? UIScrollView, scroll.contentSize.height > 2_000 { return scroll }
            return view.subviews.lazy.compactMap { verticalScroll($0) }.first
        }
        for _ in 0..<150 {
            if verticalScroll(host.view) != nil { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let scroll = try XCTUnwrap(verticalScroll(host.view))
        for _ in 0..<100 {
            if abs(scroll.contentOffset.y + scroll.adjustedContentInset.top - 64) < 1 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(scroll.contentOffset.y + scroll.adjustedContentInset.top, 64, accuracy: 1)
        XCTAssertFalse(search.revealed)
        scroll.setContentOffset(CGPoint(x: 0, y: 400), animated: false)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(search.revealed, "Normal scrolling must not open search")
        scroll.setContentOffset(CGPoint(x: 0, y: -scroll.adjustedContentInset.top - 60), animated: false)
        for _ in 0..<100 {
            if search.revealed { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(search.revealed)
        XCTAssertEqual(search.query, "", "Pulling down must not invent or reuse a global query")
        let before = scroll.adjustedContentInset.top
        search.query = "Album"
        scroll.setContentOffset(CGPoint(x: 0, y: 600), animated: false)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertFalse(search.revealed, "Scrolling up collapses the drawer")
        XCTAssertEqual(search.query, "Album", "Hiding search keeps the active filter")
        XCTAssertEqual(scroll.adjustedContentInset.top, before, accuracy: 1, "The controls are page content, not a changing pinned safe-area inset")
    }
}

@MainActor
@Observable
private final class SearchState {
    var query = ""
    var revealed = false
}

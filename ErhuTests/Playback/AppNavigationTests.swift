import XCTest
@testable import Erhu

final class AppNavigationTests: XCTestCase {
    @MainActor func testToolsKeepTheSearchAndPlayerContextUntilExplicitNavigation() {
        let router = AppRouter()
        XCTAssertEqual(router.section, .library)
        router.activate(.search)
        router.open(.album(7))
        router.open(Tool.settings)
        XCTAssertEqual(router.presentedTool, .settings)
        XCTAssertEqual(router.section, .search)
        XCTAssertEqual(router.paths[.search]?.count, 1)
        router.presentedTool = nil
        XCTAssertEqual(router.paths[.search]?.count, 1)
        router.openPlayer()
        router.open(Tool.soundCapsule)
        router.presentedTool = nil
        XCTAssertTrue(router.showsNowPlaying)
        router.activate(.library)
        XCTAssertFalse(router.showsNowPlaying)
        XCTAssertTrue(router.paths[.library]?.isEmpty == true)
    }

    @MainActor func testSectionSwitchesRetainSearchDetailsButLibraryAlwaysReturnsToRoot() {
        let router = AppRouter()
        router.activate(.search)
        router.open(.artist(9))
        router.activate(.equalizer)
        router.activate(.search)
        XCTAssertEqual(router.paths[.search]?.count, 1)
        router.activate(.library)
        router.open(.allSongs)
        router.activate(.library)
        XCTAssertTrue(router.paths[.library]?.isEmpty == true)
    }
}

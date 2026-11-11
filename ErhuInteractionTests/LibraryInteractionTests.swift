import XCTest

final class LibraryInteractionTests: XCTestCase {
    @MainActor private func launch(_ page: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--erhu-interaction-probe=" + page]
        app.launch()
        return app
    }

    @MainActor func testFullPlayerOpensClosesAndReopensWithoutArtwork() {
        checkPlayerPresentation(page: "player")
    }

    @MainActor func testFullPlayerOpensClosesAndReopensWithReducedMotion() {
        checkPlayerPresentation(page: "player-reduced-motion")
    }

    @MainActor private func checkPlayerPresentation(page: String) {
        let app = launch(page)
        let mini = app.buttons["openNowPlaying"]
        XCTAssertTrue(mini.waitForExistence(timeout: 20), "The local fixture must load into the real mini player")
        let title = app.staticTexts["nowPlayingTitle"]
        let transport = app.buttons["nowPlayingPlayPause"]
        let close = app.buttons["closeNowPlaying"]
        func waitUntilHittable(_ element: XCUIElement, timeout: TimeInterval = 10) {
            let visible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                element.exists && element.isHittable
            }, object: nil)
            let result = XCTWaiter.wait(for: [visible], timeout: timeout)
            if result != .completed {
                let hierarchy = XCTAttachment(string: app.debugDescription)
                hierarchy.name = page + "-unavailable-control"
                hierarchy.lifetime = .keepAlways
                add(hierarchy)
                let screenshot = XCTAttachment(screenshot: app.screenshot())
                screenshot.name = page + "-unavailable-control"
                screenshot.lifetime = .keepAlways
                add(screenshot)
            }
            XCTAssertEqual(result, .completed,
                           "Timed out waiting for \(element.identifier) to become hittable on \(page)")
        }
        for cycle in 0..<2 {
            // On a cold simulator the mini player can enter accessibility before
            // launch and initial library layout finish. Later presentation checks
            // retain their shorter deadline to catch close/reopen regressions.
            waitUntilHittable(mini, timeout: cycle == 0 ? 30 : 10)
            mini.tap()
            waitUntilHittable(title)
            XCTAssertEqual(title.label, "Player presentation regression")
            waitUntilHittable(transport)
            // Playback is exercised through the full-screen controls, rather than
            // just checking that an invisible overlay exists in accessibility.
            let paused = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                transport.label == "Pause"
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [paused], timeout: 10), .completed)
            transport.tap()
            let play = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                transport.label == "Play"
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [play], timeout: 5), .completed)
            transport.tap()
            waitUntilHittable(close)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = page + "-full-player"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            close.tap()
            waitUntilHittable(mini)
            XCTAssertFalse(title.exists)
        }
        mini.tap()
        waitUntilHittable(title)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.80)))
        waitUntilHittable(mini)
        mini.tap()
        waitUntilHittable(title)
        XCTAssertTrue(transport.isHittable)
    }

    @MainActor func testLargeTransportChangesTracksAndSmallTransportSeeksWithinTheTrack() {
        let app = launch("player")
        let mini = app.buttons["openNowPlaying"]
        XCTAssertTrue(mini.waitForExistence(timeout: 20))
        mini.tap()
        let title = app.staticTexts["nowPlayingTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        let next = app.buttons["nowPlayingNextTrack"]
        let previous = app.buttons["nowPlayingPreviousTrack"]
        let forward = app.buttons["nowPlayingForward"]
        let rewind = app.buttons["nowPlayingRewind"]
        XCTAssertGreaterThan(next.frame.width, forward.frame.width)
        XCTAssertGreaterThan(previous.frame.width, rewind.frame.width)
        next.tap()
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            title.label == "Second player track"
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 10), .completed)
        let playPause = app.buttons["nowPlayingPlayPause"]
        let playing = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in playPause.label == "Pause" }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [playing], timeout: 10), .completed)
        playPause.tap()
        let paused = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in playPause.label == "Play" }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [paused], timeout: 5), .completed)
        let elapsed = app.staticTexts["nowPlayingElapsed"]
        func seconds() -> Int {
            let parts = elapsed.label.split(separator: ":").compactMap { Int($0) }
            return parts.count == 2 ? parts[0] * 60 + parts[1] : -1
        }
        let initialSeconds = seconds()
        XCTAssertGreaterThanOrEqual(initialSeconds, 0)
        forward.tap()
        let advanced = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in seconds() >= initialSeconds + 9 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [advanced], timeout: 5), .completed)
        XCTAssertEqual(title.label, "Second player track")
        rewind.tap()
        let rewound = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            seconds() >= 0 && abs(seconds() - initialSeconds) <= 1
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [rewound], timeout: 5), .completed)
        XCTAssertEqual(title.label, "Second player track")
        previous.tap()
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            title.label == "Player presentation regression"
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 10), .completed)
    }

    @MainActor func testSearchClearAndCloseAreTappableWithKeyboardVisible() {
        let app = launch("search")
        app.buttons["openSearchProbe"].tap()
        let field = app.textFields["librarySearchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap(); field.typeText("needle")
        let clear = app.buttons["searchClearButton"]
        XCTAssertTrue(clear.isHittable)
        clear.tap()
        let cleared = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !clear.exists && (field.value as? String) != "needle"
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [cleared], timeout: 3), .completed)
        field.typeText("again")
        let close = app.buttons["searchCloseButton"]
        XCTAssertTrue(close.isHittable)
        close.tap()
        XCTAssertTrue(app.buttons["openSearchProbe"].waitForExistence(timeout: 5))
        XCTAssertFalse(field.exists)
    }

    @MainActor func testBrowseControlsAndRevealedSearchScrollOutOfTheViewport() {
        let app = launch("browse")
        let search = app.buttons["sectionSearchButton"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        let field = app.textFields["sectionSearchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Album")
        // Begin on page content above the keyboard: scrolling up collapses search and
        // dismisses editing while keeping the query, as in the pull-down drawer.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.40))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.17)))
        let keyboardDismissed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !app.keyboards.firstMatch.exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [keyboardDismissed], timeout: 5), .completed)
        // A text field can expose its own scroll view. Drag the page content itself.
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        start.press(forDuration: 0.05, thenDragTo: end)
        start.press(forDuration: 0.05, thenDragTo: end)
        let sort = app.staticTexts["sortProbe"]
        func frame(_ element: XCUIElement) -> String { element.exists ? String(describing: element.frame) : "hidden" }
        let details = "search=\(frame(search)), field=\(frame(field)), sort=\(frame(sort)), keyboard=\(app.keyboards.firstMatch.exists)"
        XCTAssertFalse(search.isHittable, details)
        XCTAssertFalse(field.isHittable, details)
        XCTAssertFalse(sort.isHittable, details)
    }

    @MainActor func testPullRevealsSearchBetweenTheTitleAndControlsAndUpwardSwipeCollapsesIt() {
        let app = launch("browse")
        let searchButton = app.buttons["sectionSearchButton"]
        XCTAssertTrue(searchButton.waitForExistence(timeout: 10))
        let field = app.textFields["sectionSearchField"]
        let pageReady = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            // A collapsed field leaves the accessibility tree; checking `exists` first avoids the
            // multi-second lookup retries of `isHittable` on a missing element.
            searchButton.isHittable && !(field.exists && field.isHittable)
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [pageReady], timeout: 3), .completed)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)))
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        // The accessibility element exists before the scroll/bounce animation has
        // finished. Require a usable hit target before checking its final layout.
        let revealed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            field.exists && field.isHittable
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [revealed], timeout: 3), .completed)
        XCTAssertLessThan(app.staticTexts["sectionBrowseTitle"].frame.maxY, field.frame.minY)
        XCTAssertGreaterThan(app.staticTexts["sortProbe"].frame.minY, field.frame.maxY)
        XCTAssertFalse(app.keyboards.firstMatch.exists, "Pulling reveals search without beginning editing")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)))
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !(field.exists && field.isHittable)
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 3), .completed)
    }

    @MainActor func testCarouselWrapKeepsExactlyThreeDotsAndOneHighlight() {
        let app = launch("carousel")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "smartPlaylistDot-0").firstMatch.waitForExistence(timeout: 10))
        func swipe(left: Bool) {
            // Swipe across the banner, not a small nested Play button with an inherited ID.
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: left ? 0.85 : 0.15, dy: 0.20))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: left ? 0.15 : 0.85, dy: 0.20))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        func check() {
            let dots = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "smartPlaylistDot-"))
            XCTAssertEqual(dots.count, 3)
            let selected = (0..<dots.count).filter { (dots.element(boundBy: $0).value as? String) == "Current" }
            XCTAssertEqual(selected.count, 1)
        }
        func currentPage() -> Int? {
            (0..<3).first {
                let dot = app.descendants(matching: .any).matching(identifier: "smartPlaylistDot-\($0)").firstMatch
                return (dot.value as? String) == "Current"
            }
        }
        check()
        let initial = currentPage()
        swipe(left: true); check()
        XCTAssertNotEqual(currentPage(), initial)
        for _ in 0..<2 { swipe(left: true); check() }
        XCTAssertEqual(currentPage(), initial, "Swiping past the last playlist returns the one selected dot to the start")
        for _ in 0..<3 { swipe(left: false); check() }
        XCTAssertEqual(currentPage(), initial)
    }

    #if ERHU_ANIMATED_ART
    @MainActor func testAnimatedCoverSearchStaysInTheTopNavigationDrawer() {
        let app = launch("animated-covers")
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 10))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)))
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(field.isHittable)
        XCTAssertLessThan(field.frame.maxY, app.frame.height / 2, "Animated-cover search belongs above the list, away from bottom playback/navigation controls")
    }
    #endif

    @MainActor func testFixTagsScrollingCompactsTheSharedBottomChrome() {
        let app = launch("tools")
        let fraction = app.staticTexts["chromeFraction"]
        XCTAssertTrue(fraction.waitForExistence(timeout: 10))
        // Drag the list gutter so the confidence slider cannot capture the gesture.
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.75))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.22))
        start.press(forDuration: 0.05, thenDragTo: end)
        start.press(forDuration: 0.05, thenDragTo: end)
        let compact = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (Double(fraction.label) ?? 0) > 0.5
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [compact], timeout: 3), .completed,
                       "Chrome fraction after list scrolling: \(fraction.label)")
    }

    @MainActor func testTransitionRowHasOnlyItsTitleSummaryAndSwitch() {
        let app = launch("transitions")
        XCTAssertTrue(app.buttons["transitionStudioOpen"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Enable transitions for this album"].exists)
        let wrapper = app.switches.matching(identifier: "collectionTransitionToggle").firstMatch
        XCTAssertTrue(wrapper.exists)
        // SwiftUI exposes both a wrapper and the underlying UISwitch. Use the
        // smallest hittable switch with a native binary value, rather than a
        // coordinate in the wrapper, whose frame can include non-control space.
        let candidates = app.switches.allElementsBoundByIndex.filter {
            ["0", "1"].contains($0.value as? String ?? "") && $0.isHittable
        }
        guard let toggle = candidates.min(by: {
            $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height
        }), let initialValue = toggle.value as? String else {
            XCTFail("The transition row must expose a hittable native switch: \(app.debugDescription)")
            return
        }
        let row = app.buttons["transitionStudioOpen"]
        for expectedValue in [initialValue == "1" ? "0" : "1", initialValue] {
            toggle.tap()
            let changed = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "value == %@", expectedValue), object: toggle)
            guard XCTWaiter.wait(for: [changed], timeout: 10) == .completed else {
                XCTFail("The native switch must change to \(expectedValue): \(toggle.debugDescription)")
                return
            }
            let summary = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: expectedValue == "0" ? "label CONTAINS %@" : "NOT (label CONTAINS %@)",
                                       "Off for this album"), object: row)
            guard XCTWaiter.wait(for: [summary], timeout: 10) == .completed else {
                XCTFail("The collection summary must reflect switch value \(expectedValue): \(row.label)")
                return
            }
        }
    }
}

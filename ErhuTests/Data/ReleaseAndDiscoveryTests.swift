import Foundation
import XCTest
@testable import Erhu

final class ReleaseAndDiscoveryTests: XCTestCase {
    func testNumericVersionsAndBetaOrdering() throws {
        XCTAssertLessThan(try XCTUnwrap(ReleaseVersion("v1.0-beta.2")), try XCTUnwrap(ReleaseVersion("v1.0-beta.10")))
        XCTAssertLessThan(try XCTUnwrap(ReleaseVersion("v1.0-beta")), try XCTUnwrap(ReleaseVersion("1.0.0")))
        XCTAssertLessThan(try XCTUnwrap(ReleaseVersion("1.9")), try XCTUnwrap(ReleaseVersion("1.10")))
        XCTAssertEqual(ReleaseVersion("1.0.0+build.12"), ReleaseVersion("1.0"))
        for invalid in ["", "-1", "1..0", "latest", "1.0-", "1.2.3.4"] { XCTAssertNil(ReleaseVersion(invalid), invalid) }
    }

    @MainActor func testSameBetaDoesNotOfferItselfAndNewBetaUsesCorrectVariant() {
        XCTAssertEqual(ReleaseChecker.result([release("v1.0-beta")], installed: "v1.0-beta", animated: false), .current)
        let update = release("v1.0-beta.2")
        XCTAssertEqual(ReleaseChecker.result([update], installed: "v1.0-beta", animated: false), .available(update))
        XCTAssertTrue(update.download(animated: false)!.lastPathComponent.hasSuffix("-static.ipa"))
        XCTAssertTrue(update.download(animated: true)!.lastPathComponent.hasSuffix("-animated.ipa"))
        let draft = release("v9.0", draft: true)
        XCTAssertEqual(ReleaseChecker.result([draft, release("v1.0-beta")], installed: "v1.0-beta", animated: false), .current)
    }

    @MainActor func testNetworkFailureIsNotReportedAsUpToDateAndRateLimitAvoidsRequests() async {
        let client = ReleaseHTTP(status: 429, payload: Data())
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let checker = ReleaseChecker(client: client, installed: "v1.0-beta", defaults: defaults, animated: false)
        await checker.check(manual: true)
        guard case .failed = checker.state else { return XCTFail("429 is not a current-version response") }
        await checker.check(manual: true)
        let count = await client.count
        XCTAssertEqual(count, 1)
        XCTAssertNil(checker.checkedAt)
    }

    @MainActor func testAutomaticChecksAreCachedButManualChecksStillWork() async throws {
        let client = ReleaseHTTP(status: 200, payload: try JSONEncoder().encode([release("v1.0-beta")]))
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let checker = ReleaseChecker(client: client, installed: "v1.0-beta", defaults: defaults, animated: false)
        await checker.check()
        await checker.check()
        let automatic = await client.count
        XCTAssertEqual(automatic, 1)
        await checker.check(manual: true)
        let manual = await client.count
        XCTAssertEqual(manual, 2)
        XCTAssertEqual(checker.state, .current)
    }

    @MainActor func testOlderPreferencesKeepDiscoveryAndDoNotResetTheme() throws {
        let old = Data(#"{"theme":"dark","startSection":"vybe"}"#.utf8)
        let value = try JSONDecoder().decode(AppSettings.Stored.self, from: old)
        XCTAssertTrue(value.vybeEnabled)
        XCTAssertFalse(value.introductionCompleted)
        XCTAssertEqual(value.theme, .dark)
        XCTAssertEqual(value.typeface, .system)
        XCTAssertFalse(IntroductionPage.pages(vybe: false).contains { $0.id == "vybe" })
    }

    func testLoopingPagesWrapInBothDirectionsWithoutExtraDots() {
        XCTAssertEqual(Array(LoopingPages.indices(count: 3)), [0, 1, 2, 3, 4])
        XCTAssertEqual(LoopingPages.logical(0, count: 3), 2)
        XCTAssertEqual(LoopingPages.settled(0, count: 3), 3)
        XCTAssertEqual(LoopingPages.logical(4, count: 3), 0)
        XCTAssertEqual(LoopingPages.settled(4, count: 3), 1)
        XCTAssertEqual(Array(LoopingPages.indices(count: 1)), [0])
        XCTAssertTrue(LoopingPages.indices(count: 0).isEmpty)
    }

    @MainActor func testLaunchRevalidatesCachedReleaseAndIgnoreSurvivesRelaunch() async throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let update = release("v1.0-beta.2")
        let client = ReleaseHTTP(status: 200, payload: try JSONEncoder().encode([update]))
        let checker = ReleaseChecker(client: client, installed: "v1.0-beta", defaults: defaults, animated: false)
        await checker.checkOnOpen()
        XCTAssertEqual(checker.prompt, update)
        checker.dismissPrompt(ignore: true)
        let reopened = ReleaseChecker(client: client, installed: "v1.0-beta", defaults: defaults, animated: false)
        await reopened.checkOnOpen()
        XCTAssertNil(reopened.prompt)
        XCTAssertEqual(reopened.state, .available(update), "Manual settings still show ignored updates")
        let requests = await client.count
        XCTAssertEqual(requests, 2, "A new opening revalidates even a fresh persisted cache")
        let newer = release("v1.0-beta.3")
        let next = ReleaseChecker(client: ReleaseHTTP(status: 200, payload: try JSONEncoder().encode([newer])), installed: "v1.0-beta", defaults: defaults, animated: false)
        await next.checkOnOpen()
        XCTAssertEqual(next.prompt, newer, "Ignoring one version must not hide future versions")
    }

    @MainActor func testSkipOnlyLastsForThisSessionAndCurrentBuildStaysSilent() async throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let client = ReleaseHTTP(status: 200, payload: try JSONEncoder().encode([release("v1.0-beta.2")]))
        let first = ReleaseChecker(client: client, installed: "v1.0-beta", defaults: defaults, animated: false)
        await first.checkOnOpen(); first.dismissPrompt()
        XCTAssertNil(first.prompt)
        let reopened = ReleaseChecker(client: client, installed: "v1.0-beta", defaults: defaults, animated: false)
        await reopened.checkOnOpen()
        XCTAssertNotNil(reopened.prompt)
        let current = ReleaseChecker(client: client, installed: "v1.0-beta.2", defaults: defaults, animated: false)
        await current.checkOnOpen()
        XCTAssertNil(current.prompt)
    }

    func testAmpReleaseOffersDirectIPAAndComparesBuildNumbers() throws {
        let tag = "v0.1.0-amp.25"
        let url = try XCTUnwrap(URL(string: "https://github.com/SRJW/amp/releases/download/\(tag)/amp.ipa"))
        let update = AppRelease(id: 25, tag_name: tag, name: "amp", body: nil,
                                html_url: URL(string: "https://github.com/SRJW/amp/releases/tag/\(tag)")!,
                                draft: false, prerelease: true,
                                assets: [.init(name: "amp.ipa", browser_download_url: url)])
        XCTAssertEqual(update.download(animated: false), url)
        XCTAssertNil(update.download(animated: true))
        XCTAssertEqual(ReleaseChecker.result([update], installed: "v0.1.0-amp.24", animated: false), .available(update))
        XCTAssertEqual(ReleaseChecker.result([update], installed: tag, animated: false), .current)
        XCTAssertFalse(AppRelease.official(URL(string: "https://github.com/another/repo/releases/download/v1/amp.ipa")!))
    }

    private func release(_ tag: String, draft: Bool = false) -> AppRelease {
        AppRelease(id: 1, tag_name: tag, name: tag, body: "Notes",
                   html_url: URL(string: "https://github.com/SRJW/amp/releases/tag/\(tag)")!, draft: draft, prerelease: true,
                   assets: ["static", "animated"].map { name in
                       AppRelease.Asset(name: "Erhu-\(tag)-\(name).ipa", browser_download_url: URL(string: "https://github.com/SRJW/amp/releases/download/\(tag)/Erhu-\(tag)-\(name).ipa")!)
                   })
    }
}

private actor ReleaseHTTP: HTTPClient {
    let status: Int
    let payload: Data
    private(set) var count = 0
    init(status: Int, payload: Data) { self.status = status; self.payload = payload }
    func get(_ url: URL, headers: [String: String]) async throws -> (Data, HTTPURLResponse) {
        count += 1
        return (payload, HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Retry-After": "120"])!)
    }
}

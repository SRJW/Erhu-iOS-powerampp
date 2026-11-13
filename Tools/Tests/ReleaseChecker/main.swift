import Foundation

private actor ReleaseHTTP: HTTPClient {
    let payload: Data
    private(set) var requests: [URL] = []
    init(_ payload: Data) { self.payload = payload }
    func get(_ url: URL, headers: [String: String]) async throws -> (Data, HTTPURLResponse) {
        requests.append(url)
        return (payload, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

@main struct ReleaseChecks {
    @MainActor static func main() async throws {
        let download = URL(string: "https://github.com/SRJW/amp/releases/download/v0.1.0-amp.41/amp.ipa")!
        let update = AppRelease(id: 41, tag_name: "v0.1.0-amp.41", name: "amp", body: nil,
                                html_url: URL(string: "https://github.com/SRJW/amp/releases/tag/v0.1.0-amp.41")!,
                                draft: false, prerelease: true,
                                assets: [.init(name: "amp.ipa", browser_download_url: download)])
        precondition(update.download(animated: false) == download)
        precondition(update.download(animated: true) == nil)
        precondition(ReleaseChecker.result([update], installed: "v0.1.0-amp.35", animated: false) == .available(update))
        precondition(ReleaseChecker.result([update], installed: update.tag_name, animated: false) == .current)
        precondition(!AppRelease.official(URL(string: "https://github.com/another/amp/releases/tag/v9")!))
        precondition(!AppRelease.official(URL(string: "https://github.com/SRJW/amp-malicious/releases/tag/v9")!))
        let suite = "amp-release-tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        // An old repository cache must not suppress a fresh update check.
        defaults.set(Date(), forKey: "amp.releases.checkedAt")
        defaults.set("old-etag", forKey: "amp.releases.etag")
        let client = ReleaseHTTP(try JSONEncoder().encode([update]))
        let checker = ReleaseChecker(client: client, installed: "v0.1.0-amp.35", defaults: defaults, animated: false)
        await checker.check()
        precondition(checker.state == .available(update))
        let requests = await client.requests
        precondition(requests == [URL(string: "https://api.github.com/repos/SRJW/amp/releases?per_page=30")!])
        let reopened = ReleaseChecker(client: client, installed: "v0.1.0-amp.35", defaults: defaults, animated: false)
        precondition(reopened.state == .available(update))
        // Verify that the current public GitHub response actually passes the app's decoder and filter.
        let live = ReleaseChecker(installed: "v0.1.0-amp.1", defaults: defaults, animated: false)
        await live.check(manual: true)
        guard case .available(let release) = live.state else {
            fatalError("Live GitHub release detection failed: \(live.state)")
        }
        print("Release detection passed: migrated endpoint, cache, version comparison, URL validation and live \(release.tag_name)")
    }
}

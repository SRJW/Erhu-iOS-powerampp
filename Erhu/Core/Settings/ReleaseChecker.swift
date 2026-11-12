import Foundation
import Observation

struct ReleaseVersion: Comparable, Equatable {
    let numbers: [Int]
    let suffix: [String]

    init?(_ tag: String) {
        let value = tag.lowercased().hasPrefix("v") ? String(tag.dropFirst()) : tag
        let canonical = value.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)[0]
        let parts = canonical.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let numbers = parts.first?.split(separator: ".").compactMap { Int($0) } ?? []
        guard (1...3).contains(numbers.count), numbers.count == parts[0].split(separator: ".", omittingEmptySubsequences: false).count,
              numbers.allSatisfy({ $0 >= 0 }), parts[0].allSatisfy({ $0.isNumber || $0 == "." }),
              parts.count == 1 || !parts[1].isEmpty else { return nil }
        self.numbers = numbers + Array(repeating: 0, count: 3 - numbers.count)
        suffix = parts.count == 2 ? parts[1].lowercased().split(separator: ".").map(String.init) : []
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.numbers != rhs.numbers { return lhs.numbers.lexicographicallyPrecedes(rhs.numbers) }
        if lhs.suffix.isEmpty != rhs.suffix.isEmpty { return !lhs.suffix.isEmpty }
        for (a, b) in zip(lhs.suffix, rhs.suffix) where a != b {
            if let x = Int(a), let y = Int(b) { return x < y }
            if Int(a) != nil { return true }
            if Int(b) != nil { return false }
            return a < b
        }
        return lhs.suffix.count < rhs.suffix.count
    }
}

struct AppRelease: Codable, Equatable, Sendable, Identifiable {
    struct Asset: Codable, Equatable, Sendable {
        let name: String
        let browser_download_url: URL
    }
    let id: Int64
    let tag_name: String
    let name: String?
    let body: String?
    let html_url: URL
    let draft: Bool
    let prerelease: Bool
    var published_at: String? = nil
    let assets: [Asset]

    func download(animated: Bool) -> URL? {
        assets.first {
            ($0.name.lowercased().hasSuffix(animated ? "-animated.ipa" : "-static.ipa")
                || (!animated && $0.name.lowercased() == "amp.ipa"))
                && Self.official($0.browser_download_url)
        }?.browser_download_url
    }
    static func official(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == "github.com"
            && url.path.hasPrefix("/SRJW/Erhu-iOS-powerampp/releases/")
    }
}

enum ReleaseCheckState: Equatable {
    case idle, checking, current, available(AppRelease), failed(String)
}

@MainActor @Observable
final class ReleaseChecker {
    static let shared = ReleaseChecker()
    static let interval: TimeInterval = 24 * 60 * 60
    private(set) var state: ReleaseCheckState = .idle
    private(set) var checkedAt: Date?
    private let client: any HTTPClient
    private let installed: String
    private let defaults: UserDefaults
    private let animated: Bool
    private var cooldown: Date?
    private var openedAt: Date?
    private var offeredThisSession: Set<String> = []
    private(set) var prompt: AppRelease?

    /// Revalidate with ETag on each app opening, while coalescing launch/scene callbacks.
    func checkOnOpen() async {
        let now = Date()
        if let openedAt, now.timeIntervalSince(openedAt) < 10 { return }
        openedAt = now
        await check(manual: true)
        guard case .available(let release) = state,
              !offeredThisSession.contains(release.tag_name),
              !(defaults.stringArray(forKey: Self.prefix + "ignored") ?? []).contains(release.tag_name) else { return }
        offeredThisSession.insert(release.tag_name)
        prompt = release
    }

    func dismissPrompt(ignore: Bool = false) {
        if ignore, let prompt {
            var ignored = Set(defaults.stringArray(forKey: Self.prefix + "ignored") ?? [])
            ignored.insert(prompt.tag_name)
            defaults.set(Array(ignored).sorted(), forKey: Self.prefix + "ignored")
        }
        prompt = nil
    }
    private static let prefix = "amp.releases."

    init(client: any HTTPClient = URLSessionHTTPClient(cachePolicy: .reloadIgnoringLocalCacheData),
         installed: String = Bundle.main.object(forInfoDictionaryKey: "ErhuReleaseTag") as? String ?? "v1.0-beta",
         defaults: UserDefaults = .standard, animated: Bool = BuildVariant.animated) {
        self.client = client; self.installed = installed; self.defaults = defaults; self.animated = animated
        checkedAt = defaults.object(forKey: Self.prefix + "checkedAt") as? Date
        if let data = defaults.data(forKey: Self.prefix + "releases"), let releases = try? JSONDecoder().decode([AppRelease].self, from: data) {
            state = Self.result(releases, installed: installed, animated: animated)
        }
    }

    nonisolated static func result(_ releases: [AppRelease], installed: String, animated: Bool) -> ReleaseCheckState {
        guard let current = ReleaseVersion(installed) else { return .failed("This build has no valid release version.") }
        let compatible = releases.filter { !$0.draft && AppRelease.official($0.html_url) && $0.download(animated: animated) != nil && ReleaseVersion($0.tag_name) != nil }
        guard !compatible.isEmpty else { return .failed("No published IPA for this artwork variant was found.") }
        if let newest = compatible.max(by: { ReleaseVersion($0.tag_name)! < ReleaseVersion($1.tag_name)! }),
           ReleaseVersion(newest.tag_name)! > current { return .available(newest) }
        return .current
    }

    func check(manual: Bool = false) async {
        guard state != .checking else { return }
        let now = Date()
        if let cooldown, cooldown > now {
            if manual { state = .failed("GitHub is rate-limiting requests. Try again after \(cooldown.formatted(date: .omitted, time: .shortened)).") }
            return
        }
        if !manual, let checkedAt, now.timeIntervalSince(checkedAt) < Self.interval { return }
        state = .checking
        var headers = ["Accept": "application/vnd.github+json", "User-Agent": "amp-iOS", "X-GitHub-Api-Version": "2022-11-28"]
        if let etag = defaults.string(forKey: Self.prefix + "etag") { headers["If-None-Match"] = etag }
        do {
            let (data, response) = try await client.get(URL(string: "https://api.github.com/repos/SRJW/Erhu-iOS-powerampp/releases?per_page=30")!, headers: headers)
            if response.statusCode == 403 || response.statusCode == 429 {
                let retry = response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init) ?? 3600
                cooldown = response.value(forHTTPHeaderField: "X-RateLimit-Reset").flatMap(TimeInterval.init).map(Date.init(timeIntervalSince1970:)) ?? now.addingTimeInterval(retry)
                state = .failed("GitHub temporarily limited update checks. Your app and music still work; try later.")
                return
            }
            let releases: [AppRelease]
            if response.statusCode == 304, let saved = defaults.data(forKey: Self.prefix + "releases") {
                releases = try JSONDecoder().decode([AppRelease].self, from: saved)
            } else {
                guard response.statusCode == 200 else { throw URLError(.badServerResponse) }
                releases = try JSONDecoder().decode([AppRelease].self, from: data)
                defaults.set(data, forKey: Self.prefix + "releases")
                defaults.set(response.value(forHTTPHeaderField: "ETag"), forKey: Self.prefix + "etag")
            }
            state = Self.result(releases, installed: installed, animated: animated)
            if case .failed = state { return }
            checkedAt = now
            defaults.set(now, forKey: Self.prefix + "checkedAt")
        } catch {
            state = .failed("Couldn’t check GitHub Releases. Check your connection and try again.")
            cooldown = now.addingTimeInterval(60)
        }
    }
}

enum BuildVariant {
    static var animated: Bool {
        #if ERHU_ANIMATED_ART
        true
        #else
        false
        #endif
    }
}

import Foundation

struct PlayerLaunchRequest: Equatable {
    enum Command: String { case toggle, play, pause, previous, next }
    var command: Command?

    init(command: Command? = nil) { self.command = command }
    init?(url: URL) {
        guard ["amp", "erhu"].contains(url.scheme?.lowercased() ?? ""),
              url.host?.lowercased() == "player", url.user == nil, url.port == nil,
              url.path.isEmpty || url.path == "/" else { return nil }
        let actions = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.filter { $0.name == "action" } ?? []
        guard actions.count <= 1 else { return nil }
        if let action = actions.first {
            guard let value = action.value, let command = Command(rawValue: value) else { return nil }
            self.command = command
        } else { command = nil }
    }

    static func url(command: Command? = nil) -> URL {
        var parts = URLComponents()
        parts.scheme = "amp"
        parts.host = "player"
        if let command { parts.queryItems = [URLQueryItem(name: "action", value: command.rawValue)] }
        return parts.url!
    }
}

/// Retain a launch request until queue restoration actually finishes, without a timeout race.
struct PlayerLaunchGate {
    private var pending: PlayerLaunchRequest?
    mutating func request(_ value: PlayerLaunchRequest = PlayerLaunchRequest()) { pending = value }
    mutating func take(restored: Bool) -> PlayerLaunchRequest? {
        guard restored else { return nil }
        defer { pending = nil }
        return pending
    }
}

/// A foreground App Intent can request the player without relying on a widget App Group.
enum PlayerLaunchSignal {
    static let notification = Notification.Name("amp.open-player-requested")
    private static let key = "amp.control.open-player"
    static func request(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: key)
        NotificationCenter.default.post(name: notification, object: nil)
    }
    static func consume(defaults: UserDefaults = .standard) -> Bool {
        let pending = defaults.bool(forKey: key)
        defaults.removeObject(forKey: key)
        return pending
    }
}

import Foundation

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
    checks += 1
}
func profile(_ groups: [String], format: PropertyListSerialization.PropertyListFormat = .xml) throws -> Data {
    try PropertyListSerialization.data(fromPropertyList: ["Entitlements": ["com.apple.security.application-groups": groups]], format: format, options: 0)
}
let renamed = "group.com.erhu.player.TEAM123"
let cms = Data([0x30, 0x82, 0x00, 0xff]) + (try profile([renamed, "group.other.app"])) + Data([0, 0xff])
let candidates = PlayerWidgetStorage.identifiers(profile: cms)
check(candidates.first == renamed, "Prefer the concrete group actually provisioned by the signer")
check(!candidates.contains("group.other.app"), "Do not write player state into an unrelated app group")
let wildcard = try profile(["group.*"])
check(PlayerWidgetStorage.identifiers(profile: wildcard).count == 1, "Never treat wildcard entitlements as a concrete container")
let binary = try profile([renamed], format: .binary)
check(PlayerWidgetStorage.profileGroups(binary) == [renamed], "Binary profile plist is supported")
check(PlayerWidgetStorage.profileGroups(Data([0, 1, 2])) == nil, "Invalid profile does not crash")
let expected = URL(fileURLWithPath: "/tmp/widget-test-group")
let container = PlayerWidgetStorage.resolve(identifiers: candidates) { $0 == renamed ? expected : nil }
check(container?.folder == expected && container?.group == renamed, "Resolve renamed shared storage")
check(PlayerWidgetStorage.resolve(identifiers: candidates, container: { _ in nil }) == nil, "Missing entitlements are reported rather than falling back to private app storage")
check(PlayerWidgetStorage.identifiers(profile: nil) == [PlayerWidgetStorage.defaultGroup], "Preserve standard installations without a profile")
check(PlayerWidgetStorage.identifiers(profile: nil, configured: "group.custom.amp") == ["group.custom.amp"], "Allow an explicitly configured signing group")
let legacy = Data(#"{"title":"Track","artist":"Artist","isPlaying":true,"songID":42,"hasArtwork":true}"#.utf8)
let old = try JSONDecoder().decode(PlayerWidgetSnapshot.self, from: legacy)
check(old.title == "Track" && old.artworkFileName == nil, "Existing widget snapshots still load")
var updated = old
updated.artworkFileName = "cover-track.jpg"
updated.album = "Recent album"
let roundTrip = try JSONDecoder().decode(PlayerWidgetSnapshot.self, from: JSONEncoder().encode(updated))
check(roundTrip == updated, "Current-track snapshot round trip retains its artwork identity")
for command in [PlayerLaunchRequest.Command.toggle, .play, .pause, .previous, .next] {
    check(PlayerLaunchRequest(url: PlayerLaunchRequest.url(command: command))?.command == command, "Widget links match the app's command routing")
}
check(PlayerLaunchRequest(url: URL(string: "erhu://player")!) != nil, "Legacy player links remain valid")
for invalid in ["https://player", "amp://settings", "amp://player?action=delete", "amp://player?action=next&action=previous", "amp://player/other", "amp://user@player"] {
    check(PlayerLaunchRequest(url: URL(string: invalid)!) == nil, "Reject invalid player command: \(invalid)")
}
var gate = PlayerLaunchGate()
check(gate.take(restored: true) == nil, "Ordinary launch must not force the player")
gate.request(PlayerLaunchRequest(command: .next))
check(gate.take(restored: false) == nil, "Wait for cold-launch queue restoration")
check(gate.take(restored: true)?.command == .next, "Scene activation does not overwrite the pending widget action")
check(gate.take(restored: true) == nil, "Execute each widget command exactly once")
check(gate.take(restored: true) == nil, "An ordinary scene activation must preserve the current screen")
let suite = "amp-control-test-\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
check(!PlayerLaunchSignal.consume(defaults: defaults), "No launch request initially")
PlayerLaunchSignal.request(defaults: defaults)
check(PlayerLaunchSignal.consume(defaults: defaults), "Foreground control requests the player without an App Group")
check(!PlayerLaunchSignal.consume(defaults: defaults), "Consume a control launch request only once")
print("Passed \(checks) widget storage and playback launch checks")

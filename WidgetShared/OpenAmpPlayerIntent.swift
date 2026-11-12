import AppIntents

/// Runs in the foreground app; opening the player does not require shared widget storage.
struct OpenAmpPlayerIntent: AppIntent {
    static var title: LocalizedStringResource = "Open amp"
    static var description = IntentDescription("Open amp at the current song.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        PlayerLaunchSignal.request()
        return .result()
    }
}

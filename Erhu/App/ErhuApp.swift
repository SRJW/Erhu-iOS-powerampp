import SwiftUI

@main
struct ErhuApp: App {
    @State private var services = AppServices.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var returningFromBackground = false

    var body: some Scene {
        WindowGroup {
            ThemedRoot { appContent }
                .environment(services.library)
                .environment(services.player)
                .environment(services.actions)
                .environment(services.mixes)
                .environment(services.vybe)
                .environment(services.search)
                .environment(services.router)
                .environment(services.settings)
                .environment(services.sound)
                .environment(services.lyrics)
                .environment(services.transfer)
                .environment(services.fixTags)
                .environment(services.artwork)
                .environment(services.transitions)
                .preferredColorScheme(services.settings.colorScheme)
                .onOpenURL { url in handlePlayerURL(url) }
                .onContinueUserActivity("com.erhu.nowplaying") { _ in services.router.showsNowPlaying = true }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background { returningFromBackground = true }
                    if phase == .active, returningFromBackground {
                        returningFromBackground = false
                        if services.player.state.currentSong != nil { services.router.showsNowPlaying = true }
                    }
                }
        }
    }

    private func handlePlayerURL(_ url: URL) {
        guard url.scheme?.lowercased() == "erhu", url.host?.lowercased() == "player" else { return }
        let action = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "action" }?.value
        Task { @MainActor in
            for _ in 0..<200 {
                if services.player.restoreFinished { break }
                try? await Task.sleep(for: .milliseconds(50))
            }
            switch action {
            case "toggle": services.player.togglePlayPause()
            case "next": services.player.skipNext()
            case "previous": services.player.skipPrevious()
            default: break
            }
            services.router.showsNowPlaying = true
        }
    }

    @ViewBuilder private var appContent: some View {
        #if DEBUG
        if let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--erhu-interaction-probe=") }),
           let page = argument.split(separator: "=").last {
            InteractionProbeView(page: String(page))
        } else { RootView() }
        #else
        RootView()
        #endif
    }

}

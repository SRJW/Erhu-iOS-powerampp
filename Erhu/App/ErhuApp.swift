import SwiftUI

@main
struct ErhuApp: App {
    @State private var services = AppServices.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var playerLaunch = PlayerLaunchGate()

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
                .onOpenURL { url in
                    guard let request = PlayerLaunchRequest(url: url) else { return }
                    playerLaunch.request(request)
                    openRequestedPlayer()
                }
                .onReceive(NotificationCenter.default.publisher(for: PlayerLaunchSignal.notification)) { _ in
                    if PlayerLaunchSignal.consume() {
                        playerLaunch.request()
                        openRequestedPlayer()
                    }
                }
                .onContinueUserActivity("com.erhu.nowplaying") { _ in
                    playerLaunch.request()
                    openRequestedPlayer()
                }
                .userActivity("com.erhu.nowplaying", isActive: services.player.state.currentSong != nil) { activity in
                    activity.title = services.player.state.currentSong?.title
                    activity.userInfo = services.player.state.currentSong.map { ["songID": $0.id] }
                    activity.targetContentIdentifier = services.player.state.currentSong.map { "amp.track.\($0.id)" }
                }
                .onChange(of: services.player.restoreFinished, initial: true) { _, ready in
                    if ready {
                        openRequestedPlayer()
                        services.player.refreshSystemPlayback()
                    }
                }
                .onChange(of: scenePhase, initial: true) { _, phase in
                    if phase == .inactive || phase == .background { playerLaunch.resume() }
                    if phase == .active {
                        if PlayerLaunchSignal.consume() { playerLaunch.request() }
                        openRequestedPlayer()
                        services.player.refreshSystemPlayback()
                    }
                }
        }
    }

    private func openRequestedPlayer() {
        guard let request = playerLaunch.take(restored: services.player.restoreFinished) else { return }
        switch request.command {
        case .toggle: services.player.togglePlayPause()
        case .play: services.player.play()
        case .pause: services.player.pause()
        case .next: services.player.skipNext()
        case .previous: services.player.skipPrevious()
        case nil: break
        }
        if services.player.state.currentSong != nil { services.router.showsNowPlaying = true }
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

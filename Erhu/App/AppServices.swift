import Foundation

/// The app's long-lived objects (Android's Hilt singletons).
@MainActor
final class AppServices {
    static let shared = AppServices()

    let database: LibraryDatabase
    let library: LibraryStore
    let transitions: TransitionSettingsStore
    let player: PlayerController
    let mixes: MixStore
    let actions: LibraryActions
    let search: SearchStore
    let router: AppRouter
    let settings: AppSettings
    let sound: SoundStore
    let lyrics: LyricsStore
    let transfer: WifiTransferStore
    let fixTags: FixTagsStore
    let artwork: ArtworkFetcherStore
    let waveforms: WaveformStore

    private init() {
        // A database that cannot be opened falls back to memory: the app still works this session.
        database = (try? LibraryDatabase.open()) ?? (try! LibraryDatabase.inMemory())
        library = LibraryStore(database: database)
        transitions = TransitionSettingsStore()
        player = PlayerController(database: database, transitions: transitions)
        mixes = MixStore(database: database)
        actions = LibraryActions(database: database, player: player, mixes: mixes)
        search = SearchStore(library: library)
        settings = AppSettings()
        sound = SoundStore(kernel: player.engine.eqKernel)
        lyrics = LyricsStore(database: database,
                             repository: OnlineLyricsRepository(providers: [LrclibProvider(), LyricsOvhProvider()],
                                 cache: FileOnlineLyricsCache(folder: LibraryPaths.cachesFolder.appending(path: "online-lyrics")),
                                 downloads: FileOnlineLyricsCache(folder: LibraryPaths.supportFolder.appending(path: "lyrics-downloads")),
                                 legacy: FileOnlineLyricsCache()))
        router = AppRouter()
        transfer = WifiTransferStore(library: library)
        fixTags = FixTagsStore(library: library)
        artwork = ArtworkFetcherStore(library: library, service: fixTags.service)
        waveforms = WaveformStore(database: database)
        artwork.startAutomaticMatching()
    }
}

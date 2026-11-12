import UIKit
import WidgetKit

@MainActor
enum PlayerWidgetPublisher {
    private static var previous: PlayerWidgetSnapshot?
    private static var previousImage: UIImage?
    private(set) static var lastError: String?

    static func publish(song: Song?, playing: Bool, forceReload: Bool = false) {
        guard let folder = PlayerWidgetSnapshot.folder else {
            lastError = "The installed signature does not provide a shared App Group for amp and its widget. Preserve the extension and provision the same group for both when signing."
            return
        }
        let image = song.flatMap { ArtworkLoader.shared.cachedImage(for: $0.url, maxPixels: 600, fallbackSizes: [1200, 400, 300, 150, 120, 80]) }
        var value = PlayerWidgetSnapshot(title: song?.title ?? "amp", artist: song?.artist ?? "Open your music",
                                        isPlaying: playing, songID: song?.id, hasArtwork: image != nil)
        value.artworkFileName = previous?.artworkFileName
        guard forceReload || value != previous || image !== previousImage else { return }
        do {
            if image !== previousImage || (image != nil && value.artworkFileName == nil) {
                if let data = image?.jpegData(compressionQuality: 0.45) {
                    let name = "cover-\(UUID().uuidString).jpg"
                    try data.write(to: folder.appendingPathComponent(name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                    value.artworkFileName = name
                } else {
                    value.artworkFileName = nil
                    value.hasArtwork = false
                }
            }
            // Commit metadata only after its own uniquely named artwork has been written.
            try JSONEncoder().encode(value).write(to: folder.appendingPathComponent("player.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            previous = value
            previousImage = image
            lastError = nil
            WidgetCenter.shared.reloadTimelines(ofKind: PlayerWidgetSnapshot.kind)
            pruneArtwork(in: folder, keeping: value.artworkFileName)
        } catch {
            lastError = "Couldn't share the current song with the widget: \(error.localizedDescription)"
        }
    }

    private static func pruneArtwork(in folder: URL, keeping current: String?) {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        func modified(_ url: URL) -> Date {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            return values?.contentModificationDate ?? .distantPast
        }
        let covers = files.filter { $0.lastPathComponent.hasPrefix("cover-") && $0.pathExtension == "jpg" }
            .sorted { modified($0) > modified($1) }
        for old in covers.dropFirst(4) where old.lastPathComponent != current { try? FileManager.default.removeItem(at: old) }
    }
}

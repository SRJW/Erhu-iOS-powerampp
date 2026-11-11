import UIKit
import WidgetKit

@MainActor
enum PlayerWidgetPublisher {
    private static var previous: PlayerWidgetSnapshot?
    static func publish(song: Song?, playing: Bool) {
        let image = song.flatMap { ArtworkLoader.shared.cachedImage(for: $0.url, maxPixels: 600, fallbackSizes: [1200, 400, 300, 150, 120, 80]) }
        let value = PlayerWidgetSnapshot(title: song?.title ?? "Erhu", artist: song?.artist ?? "Open your music",
                                        isPlaying: playing, songID: song?.id, hasArtwork: image != nil)
        guard value != previous, let folder = PlayerWidgetSnapshot.folder else { return }
        do {
            if let image, let data = image.jpegData(compressionQuality: 0.45) {
                try data.write(to: folder.appendingPathComponent("cover.jpg"), options: .atomic)
            } else { try? FileManager.default.removeItem(at: folder.appendingPathComponent("cover.jpg")) }
            try JSONEncoder().encode(value).write(to: folder.appendingPathComponent("player.json"), options: .atomic)
            previous = value
            WidgetCenter.shared.reloadTimelines(ofKind: PlayerWidgetSnapshot.kind)
        } catch { /* Keep the last complete widget snapshot if shared storage is unavailable. */ }
    }
}

import SwiftUI
import WidgetKit
import UIKit

private struct PlayerEntry: TimelineEntry {
    let date: Date
    let snapshot: PlayerWidgetSnapshot
}
private struct PlayerProvider: TimelineProvider {
    func placeholder(in context: Context) -> PlayerEntry { PlayerEntry(date: .now, snapshot: .empty) }
    func getSnapshot(in context: Context, completion: @escaping (PlayerEntry) -> Void) {
        completion(PlayerEntry(date: .now, snapshot: .load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<PlayerEntry>) -> Void) {
        completion(Timeline(entries: [PlayerEntry(date: .now, snapshot: .load())], policy: .after(Date().addingTimeInterval(900))))
    }
}
private struct PlayerWidgetView: View {
    let entry: PlayerEntry
    @Environment(\.widgetFamily) private var family
    private var cover: UIImage? {
        guard entry.snapshot.hasArtwork, let folder = PlayerWidgetSnapshot.folder else { return nil }
        return UIImage(contentsOfFile: folder.appendingPathComponent("cover.jpg").path)
    }
    var body: some View {
        HStack(spacing: 12) {
            if family == .systemMedium {
                artwork.frame(width: 76, height: 76).clipShape(RoundedRectangle(cornerRadius: 12))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.snapshot.title).font(.headline).lineLimit(1)
                Text(entry.snapshot.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 2)
                if family == .systemSmall {
                    // Small widgets have a single link destination. Do not draw
                    // three independent controls that the system cannot activate.
                    Label("Open player", systemImage: entry.snapshot.isPlaying ? "waveform" : "play.fill")
                        .font(.caption.bold())
                } else {
                    HStack {
                        command("backward.fill", action: "previous", label: "Previous track")
                        Spacer()
                        command(entry.snapshot.isPlaying ? "pause.fill" : "play.fill", action: "toggle", label: entry.snapshot.isPlaying ? "Pause" : "Play")
                        Spacer()
                        command("forward.fill", action: "next", label: "Next track")
                    }.font(.title3.bold())
                }
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "erhu://player"))
    }
    @ViewBuilder private var artwork: some View {
        if let cover { Image(uiImage: cover).resizable().scaledToFill() }
        else { RoundedRectangle(cornerRadius: 12).fill(.secondary.opacity(0.15)).overlay { Image(systemName: "music.note").font(.largeTitle) } }
    }
    private func command(_ symbol: String, action: String, label: String) -> some View {
        Link(destination: URL(string: "erhu://player?action=" + action)!) {
            Image(systemName: symbol).frame(minWidth: 32, minHeight: 36)
        }.accessibilityLabel(label)
    }
}
@main
struct ErhuPlayerWidget: Widget {
    let kind = PlayerWidgetSnapshot.kind
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PlayerProvider()) { PlayerWidgetView(entry: $0) }
            .configurationDisplayName("Erhu Player")
            .description("Your current song, with controls that open Erhu to control playback.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

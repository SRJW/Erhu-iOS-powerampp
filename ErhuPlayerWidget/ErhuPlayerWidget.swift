import SwiftUI
import WidgetKit
import UIKit
import AppIntents

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
        completion(Timeline(entries: [PlayerEntry(date: .now, snapshot: .load())], policy: .after(Date().addingTimeInterval(300))))
    }
}
private struct PlayerWidgetView: View {
    let entry: PlayerEntry
    @Environment(\.widgetFamily) private var family
    private var cover: UIImage? {
        guard entry.snapshot.hasArtwork, let folder = PlayerWidgetSnapshot.folder else { return nil }
        return UIImage(contentsOfFile: folder.appendingPathComponent(entry.snapshot.artworkFileName ?? "cover.jpg").path)
    }
    private var heading: String {
        if entry.snapshot.songID == nil { return "AMP" }
        return entry.snapshot.isPlaying ? "NOW PLAYING" : "RECENTLY PLAYED"
    }
    private var title: String {
        if !entry.snapshot.isPlaying, let album = entry.snapshot.album, !album.isEmpty { return album }
        return entry.snapshot.title
    }
    var body: some View {
        GeometryReader { geometry in
            if family == .systemMedium {
                HStack(spacing: 16) {
                    artwork.frame(width: geometry.size.height - 32, height: geometry.size.height - 32)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Spacer()
                            Image(systemName: "music.note").font(.system(size: 22, weight: .semibold))
                        }
                        Spacer(minLength: 0)
                        Text(heading).font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))
                        Text(title).font(.system(size: 17, weight: .bold)).lineLimit(1).minimumScaleFactor(0.8)
                        Text(entry.snapshot.artist).font(.system(size: 16)).lineLimit(1)
                            .foregroundStyle(.white.opacity(0.6))
                        Link(destination: PlayerLaunchRequest.url(command: entry.snapshot.songID == nil ? nil : (entry.snapshot.isPlaying ? .pause : .play))) {
                            Label(entry.snapshot.songID == nil ? "Open amp" : (entry.snapshot.isPlaying ? "Pause" : "Play"), systemImage: entry.snapshot.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .padding(.horizontal, 14).padding(.vertical, 7)
                                .background(.white.opacity(0.11), in: Capsule())
                        }.padding(.top, 5)
                    }
                }.padding(16)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    artwork.frame(height: max(geometry.size.height - 80, 36))
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                    Text(heading).font(.system(size: 8, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
                    Text(title).font(.system(size: 13, weight: .bold)).lineLimit(1)
                    Text(entry.snapshot.artist).font(.system(size: 11)).lineLimit(1).foregroundStyle(.white.opacity(0.6))
                }.padding(12)
            }
        }
        .foregroundStyle(.white)
        .containerBackground(for: .widget) {
            LinearGradient(colors: [Color(white: 0.22), Color(white: 0.075)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 0.75)
                }
        }
        .widgetURL(PlayerLaunchRequest.url())
    }
    @ViewBuilder private var artwork: some View {
        if let cover {
            if #available(iOS 18.0, *) {
                Image(uiImage: cover).resizable().widgetAccentedRenderingMode(.fullColor).scaledToFill()
            } else {
                Image(uiImage: cover).resizable().scaledToFill()
            }
        } else {
            Rectangle().fill(.white.opacity(0.06))
                .overlay { Image(systemName: "music.note").font(.largeTitle).foregroundStyle(.white.opacity(0.65)) }
        }
    }
}
struct ErhuPlayerWidget: Widget {
    let kind = PlayerWidgetSnapshot.kind
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PlayerProvider()) { PlayerWidgetView(entry: $0) }
            .configurationDisplayName("amp Player")
            .description("Your current or recently played music, with artwork and a Play button.")
            .supportedFamilies([.systemSmall, .systemMedium])
            .contentMarginsDisabled()
    }
}

@available(iOS 18.0, *)
struct AmpPlayerControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.erhu.player.open") {
            ControlWidgetButton(action: OpenAmpPlayerIntent()) {
                Label("amp", systemImage: "play.circle.fill")
            }
        }
        .displayName("Open amp")
        .description("Open amp at the current song.")
    }
}

@main
struct AmpWidgetBundle: WidgetBundle {
    var body: some Widget {
        ErhuPlayerWidget()
        if #available(iOS 18.0, *) { AmpPlayerControl() }
    }
}

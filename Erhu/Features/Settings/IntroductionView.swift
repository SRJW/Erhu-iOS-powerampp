import SwiftUI

struct IntroductionPage: Identifiable {
    let id: String
    let title: String
    let text: String
    let symbol: String
    static func pages() -> [Self] {
        var pages: [Self] = [
            .init(id: "welcome", title: "Your music. Your space.", text: "A home for the music you own. Your collection and listening history stay on this iPhone.", symbol: "music.note.house"),
            .init(id: "library", title: "Bring your collection", text: "Use + to choose files, or start Wi-Fi Transfer to send music from a computer. Browse your albums, artists and playlists.", symbol: "square.and.arrow.down"),
            .init(id: "tools", title: "Give music its details", text: "Find Artwork Fetcher and Auto Fix Tags in the menu or Settings. Review matches before applying changes. Online searches send the metadata needed by the provider.", symbol: "wand.and.stars"),
            .init(id: "listen", title: "Make yourself at home", text: "Tap the mini-player to open Now Playing. Swipe the artwork to change tracks, manage Queue, and follow synced lyrics when available.", symbol: "play.rectangle"),
            .init(id: "sound", title: "Shape the handover", text: "Use the eight-band EQ for your sound. Open Transition Studio from an album or playlist to edit its crossfades, or select a track pair to inspect waveforms and preview the handover.", symbol: "waveform.path"),
        ]
        pages.append(.init(id: "ready", title: "Ready when you are", text: "You can revisit this introduction in Settings → About amp. No amp account or music subscription is needed.", symbol: "checkmark.circle"))
        return pages
    }
}

struct IntroductionView: View {
    var firstLaunch = false
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @State private var selected = "welcome"
    private var pages: [IntroductionPage] { IntroductionPage.pages() }
    private var index: Int { pages.firstIndex { $0.id == selected } ?? 0 }

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            VStack(spacing: Spacing.lg) {
                TabView(selection: $selected) {
                    ForEach(pages) { page in
                        ScrollView {
                            VStack(spacing: Spacing.xl) {
                                if page.id == "welcome" {
                                    Image("AmpLogo").resizable().scaledToFit().frame(width: 120, height: 120).accessibilityHidden(true)
                                } else {
                                    Image(systemName: page.symbol).font(.system(size: 72)).foregroundStyle(palette.primary).padding(.vertical, 30).accessibilityHidden(true)
                                }
                                Text(page.title).font(.largeTitle.bold()).multilineTextAlignment(.center)
                                Text(page.text).font(.body).foregroundStyle(palette.onSurfaceVariant).multilineTextAlignment(.center)
                            }.padding(Spacing.xl)
                        }.tag(page.id)
                    }
                }.tabViewStyle(.page(indexDisplayMode: .never))
                Text("\(index + 1) of \(pages.count)").font(.caption).foregroundStyle(.secondary)
                Button(index == pages.count - 1 ? "Start listening" : "Continue") {
                    if index == pages.count - 1 { finish() }
                    else { withAnimation { selected = pages[index + 1].id } }
                }.modifier(PaletteFilledButton()).controlSize(.large).padding(.bottom)
            }
            .background(palette.background).foregroundStyle(palette.onSurface)
            .navigationTitle("Welcome to amp").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(firstLaunch ? "Skip" : "Done", action: finish) } }
        }
    }

    private func finish() {
        if firstLaunch { settings.introductionCompleted = true }
        dismiss()
    }
}

private struct VybeEnabledKey: EnvironmentKey { static let defaultValue = true }
extension EnvironmentValues {
    var vybeEnabled: Bool {
        get { self[VybeEnabledKey.self] }
        set { self[VybeEnabledKey.self] = newValue }
    }
}

import SwiftUI
import UniformTypeIdentifiers
import UIKit

enum SettingsPageRoute: String, Hashable { case appearance, visualizer, playback, library, metadata, about }

struct SettingsDestinationView: View {
    let page: SettingsPageRoute
    var body: some View {
        Group {
            switch page {
            case .appearance: AppearanceSettingsView()
            case .visualizer: VisualizerSettingsView()
            case .playback: PlaybackSettingsView()
            case .library: LibrarySettingsView()
            case .metadata: MetadataSettingsView()
            case .about: AboutSettingsView()
            }
        }.modifier(ToolPageAppearance())
    }
}

/// The Android settings groups, adapted to the controls and tools available on iOS.
struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    var body: some View {
        @Bindable var settings = settings
        SettingsPage {
            SettingsGroup("Personalize") {
                SettingsLink("Themes & Appearance", subtitle: "Colours, themes and appearance", icon: "paintpalette.fill", page: .appearance)
            }
            SettingsGroup("Sound") {
                SettingsLink("Playback", subtitle: "Crossfade and waveform mode", icon: "waveform", page: .playback)
                SettingsLink("Audio & Equalizer", subtitle: "8-band equalizer, presets and audio effects", icon: "chart.bar.fill", tool: .equalizer)
                SettingsLink("Visualizer", subtitle: "Style and feel of the Now Playing visualizer", icon: "waveform", page: .visualizer)
            }
            SettingsGroup("Library") {
                SettingsLink("Music Library", subtitle: "Music folder, scanning and your collection", icon: "folder.fill", page: .library)
                SettingsLink("Metadata & Artwork", subtitle: "Tags, cover art and online sources", icon: "number", page: .metadata)
            }
            SettingsGroup("About") {
                SettingsLink("About amp", subtitle: "Version, privacy and source code", icon: "info.circle.fill", page: .about)
            }
        }
        .navigationTitle("Settings")
    }
}

private struct SettingsPage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(spacing: 26) { content }
                .padding(Spacing.lg)
                .padding(.bottom, AppNavigationMetrics.reservedHeight + Spacing.lg)
        }
        .modifier(ToolPageAppearance())
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SettingsChoice<Leading: View>: View {
    let title: String
    let subtitle: String
    let selected: Bool
    let choose: () -> Void
    @ViewBuilder let leading: Leading
    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: choose) {
            HStack(spacing: Spacing.lg) {
                leading.frame(width: 40, height: 40).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(title).font(.body.weight(.semibold)).foregroundStyle(palette.onSurface)
                    Text(subtitle).font(.subheadline).foregroundStyle(palette.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.title3).foregroundStyle(selected ? palette.primary : palette.onSurfaceVariant)
            }
            .padding(Spacing.lg)
            .frame(minHeight: 88)
            .contentShape(Rectangle())
        }
        .pressable()
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct SettingsValueRow<Value: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let value: Value

    var body: some View {
        HStack(spacing: Spacing.lg) {
            SettingsIcon(symbol: icon)
            Text(title).frame(maxWidth: .infinity, alignment: .leading)
            value.labelsHidden()
        }
        .padding(Spacing.lg)
    }
}

private struct ThemeSwatch: View {
    let choice: ThemeChoice
    @Environment(PlayerController.self) private var player
    @Environment(\.palette) private var palette

    var body: some View {
        switch choice {
        case .system:
            Image(systemName: "circle.lefthalf.filled").resizable().foregroundStyle(palette.onSurface)
        case .light:
            Circle().fill(.white).overlay(Circle().strokeBorder(.gray.opacity(0.5)))
                .overlay(Circle().fill(.black.opacity(0.8)).padding(13))
        case .dark:
            Circle().fill(.black).overlay(Circle().strokeBorder(.white.opacity(0.2)))
                .overlay(Circle().fill(.white).padding(13))
        case .artwork:
            if let song = player.state.currentSong {
                SongArtworkView(song: song, maxPixels: 100).clipShape(Circle())
            } else {
                Circle().fill(AngularGradient(colors: [.cyan, .blue, .purple, .pink, .cyan], center: .center))
            }
        }
    }
}

private extension ThemeChoice {
    var settingsDescription: String {
        switch self {
        case .system: "Light or dark, following your iPhone"
        case .light: "A bright, clean appearance"
        case .dark: "A darker look for your library"
        case .artwork: "Artwork colours, following light or dark mode"
        }
    }
}

private struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @Environment(\.palette) private var palette

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(palette.onSurfaceVariant)
                .padding(.horizontal, Spacing.lg)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 0) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }
}

private struct SettingsIcon: View {
    let symbol: String
    @Environment(\.palette) private var palette
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 40

    var body: some View {
        Image(systemName: symbol)
            .font(.body.weight(.semibold))
            .foregroundStyle(palette.onSurface)
            .frame(width: size, height: size)
            .background(palette.onSurface.opacity(0.09), in: Circle())
            .accessibilityHidden(true)
    }
}

private struct SettingsLink: View {
    let title: String
    let subtitle: String
    let icon: String
    let route: Route
    @Environment(\.palette) private var palette

    init(_ title: String, subtitle: String, icon: String, page: SettingsPageRoute) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.route = .settingsPage(page)
    }

    init(_ title: String, subtitle: String, icon: String, tool: Tool) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.route = .tool(tool)
    }

    var body: some View {
        NavigationLink(value: route) { row }.pressable()
    }

    private var row: some View {
        HStack(spacing: Spacing.lg) {
            SettingsIcon(symbol: icon)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title).font(.body.weight(.semibold)).foregroundStyle(palette.onSurface)
                Text(subtitle).font(.subheadline).foregroundStyle(palette.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.onSurfaceVariant)
                .accessibilityHidden(true)
        }
        .padding(Spacing.lg)
        .frame(minHeight: 88)
        .contentShape(Rectangle())
    }
}

private struct AppearanceSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @State private var importingTheme = false
    @State private var themeMessage: String?

    var body: some View {
        SettingsPage {
            SettingsGroup("App theme") {
                ForEach(ThemeChoice.allCases) { choice in
                    SettingsChoice(title: choice.label, subtitle: choice.settingsDescription,
                                   selected: settings.customTheme == nil && settings.theme == choice, choose: {
                        settings.useCustomTheme(nil)
                        settings.theme = choice
                    }) { ThemeSwatch(choice: choice) }
                }
                ForEach(settings.importedThemes) { theme in
                    SettingsChoice(title: theme.name, subtitle: "By \(theme.author)",
                                   selected: settings.customTheme?.id == theme.id, choose: { settings.useCustomTheme(theme.id) }) {
                        Circle().fill(theme.palette.surface).overlay(Circle().fill(theme.palette.primary).padding(10))
                    }
                }
            }
            SettingsGroup("Your themes") {
                Button { importingTheme = true } label: {
                    Label("Import a theme…", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity, alignment: .leading).padding(Spacing.lg)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if let theme = settings.customTheme {
                    Button(role: .destructive) { settings.deleteTheme(theme.id) } label: {
                        Label("Delete \(theme.name)", systemImage: "trash")
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(Spacing.lg)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if let themeMessage { Text(themeMessage).font(.footnote).foregroundStyle(.secondary).padding(Spacing.lg) }
            }
            SettingsGroup("Typeface") {
                Picker("App font", selection: Binding(get: { settings.typeface }, set: { settings.typeface = $0 })) {
                    ForEach(AppTypeface.allCases) { font in Text(font.label).fontDesign(font.design).tag(font) }
                }.padding(Spacing.lg)
            }
            PlayerBackgroundSettingsGroup()
            Text("For system appearance and transparency options, open iPhone Settings → Accessibility → Display & Text Size. Liquid Glass options also depend on your iOS version.")
                .font(.footnote).foregroundStyle(.secondary)
            Text("Import colours from an Android theme ZIP or its manifest.json.")
                .font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
        }
        .fileImporter(isPresented: $importingTheme, allowedContentTypes: [.zip, .json]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let theme = try ThemeImporter.theme(from: try Data(contentsOf: url))
                settings.importTheme(theme)
                themeMessage = "Imported \(theme.name)."
            } catch {
                themeMessage = error.localizedDescription
            }
        }
        .navigationTitle("Themes & Appearance")
    }
}

private struct PlayerBackgroundSettingsGroup: View {
    @Environment(AppSettings.self) private var settings
    @Environment(PlayerController.self) private var player
    @Environment(\.playbackPalette) private var palette

    private var gradientColor: Binding<Color> {
        Binding(get: { Color(argb: settings.playerBackground.gradientColor) }, set: { color in
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            guard UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a) else { return }
            var appearance = settings.playerBackground
            appearance.gradientColor = 0xFF000000 | UInt32(r * 255) << 16 | UInt32(g * 255) << 8 | UInt32(b * 255)
            settings.playerBackground = appearance
        })
    }
    private func value(_ key: WritableKeyPath<PlayerBackgroundSettings, Double>) -> Binding<Double> {
        Binding(get: { settings.playerBackground[keyPath: key] }, set: {
            var appearance = settings.playerBackground
            appearance[keyPath: key] = $0
            settings.playerBackground = appearance
        })
    }
    var body: some View {
        SettingsGroup(PlayerBackgroundControls.title) {
            VStack(spacing: Spacing.lg) {
                if let song = player.state.currentSong {
                    PlayerFullBleedBackground(dominant: palette.primary, appearance: settings.playerBackground) {
                        SongArtworkView(song: song, maxPixels: 600)
                    }
                    .frame(height: 180).clipShape(RoundedRectangle(cornerRadius: Radius.medium))
                }
                slider(PlayerBackgroundControls.gradient, key: \.gradient, range: PlayerBackgroundControls.unitRange)
                ColorPicker(PlayerBackgroundControls.gradientColor, selection: gradientColor, supportsOpacity: false)
                slider(PlayerBackgroundControls.fade, key: \.fadeStart, range: PlayerBackgroundControls.unitRange)
                slider(PlayerBackgroundControls.blur, key: \.blur, range: PlayerBackgroundControls.blurRange, percent: false)
                slider(PlayerBackgroundControls.details, key: \.details, range: PlayerBackgroundControls.unitRange)
                slider(PlayerBackgroundControls.intensity, key: \.intensity, range: PlayerBackgroundControls.unitRange)
                slider(PlayerBackgroundControls.saturation, key: \.saturation, range: PlayerBackgroundControls.saturationRange)
                Button(PlayerBackgroundControls.reset) { settings.playerBackground = PlayerBackgroundSettings() }
                    .frame(minHeight: 44)
            }.padding(Spacing.lg)
        }
    }
    private func slider(_ title: String, key: WritableKeyPath<PlayerBackgroundSettings, Double>, range: ClosedRange<Double>, percent: Bool = true) -> some View {
        VStack(alignment: .leading) {
            LabeledContent(title, value: percent ? "\(Int(settings.playerBackground[keyPath: key] * 100))%" : "\(Int(settings.playerBackground[keyPath: key]))")
            Slider(value: value(key), in: range).accessibilityLabel(title)
        }
    }
}

private struct VisualizerSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.playbackPalette) private var playbackPalette
    @State private var showingVisualizer = false

    var body: some View {
        @Bindable var settings = settings
        SettingsPage {
            SettingsGroup("Style") {
                ForEach(VisualizerMode.allCases, id: \.self) { mode in
                    SettingsChoice(title: mode.label, subtitle: description(mode), selected: settings.visualizer.mode == mode,
                                   choose: { settings.visualizer.mode = mode }) {
                        SettingsIcon(symbol: mode == .circularSpectrum ? "circle.dotted" : mode == .spectrumBars ? "chart.bar.fill" : "waveform")
                    }
                }
            }
            SettingsGroup("Response") {
                SettingsValueRow(title: "Sensitivity", icon: "waveform.path") {
                    Picker("Sensitivity", selection: $settings.visualizer.sensitivity) {
                        Text("Low").tag(VisualizerSensitivity.low)
                        Text("Normal").tag(VisualizerSensitivity.normal)
                        Text("High").tag(VisualizerSensitivity.high)
                    }
                }
                SettingsValueRow(title: "Smoothing", icon: "slider.horizontal.3") {
                    Picker("Smoothing", selection: $settings.visualizer.smoothing) {
                        Text("Responsive").tag(VisualizerSmoothing.responsive)
                        Text("Balanced").tag(VisualizerSmoothing.balanced)
                        Text("Smooth").tag(VisualizerSmoothing.smooth)
                    }
                }
                SettingsValueRow(title: "Reduce motion", icon: "figure.walk.motion") {
                    Toggle("Reduce motion", isOn: $settings.visualizer.reduceMotion)
                }
            }
            SettingsGroup("Now Playing") {
                Button { showingVisualizer = true } label: {
                    Label("Open visualizer", systemImage: "waveform")
                        .frame(maxWidth: .infinity, alignment: .leading).padding(Spacing.lg)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showingVisualizer) {
            VisualizerView().environment(\.palette, playbackPalette).tint(playbackPalette.primary)
        }
        .navigationTitle("Visualizer")
    }

    private func description(_ mode: VisualizerMode) -> String {
        switch mode {
        case .spectrumBars: "Frequency bars that follow the music"
        case .circularSpectrum: "A spectrum around the album artwork"
        case .oscilloscope: "A flowing waveform of the audio"
        }
    }
}

private struct LibrarySettingsView: View {
    @Environment(LibraryStore.self) private var library

    var body: some View {
        SettingsPage {
            SettingsGroup("Music folder") {
                HStack(spacing: Spacing.lg) {
                    SettingsIcon(symbol: "folder.fill")
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("On My iPhone › Erhu").font(.headline)
                        Text("Add music with Files, the + button, or Wi-Fi Transfer.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }.padding(Spacing.lg)
            }
            SettingsGroup("Scan") {
                Button { library.scan() } label: {
                    HStack(spacing: Spacing.lg) {
                        SettingsIcon(symbol: "arrow.clockwise")
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("Rescan library now").font(.headline)
                            Text("Find new, changed and removed music").font(.subheadline).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.padding(Spacing.lg)
                }
                .buttonStyle(.plain)
                .disabled(library.isScanning)
                if let progress = library.scanProgress {
                    HStack(spacing: Spacing.md) {
                        ProgressView()
                        Text("Scanning \(progress.scanned) of \(progress.total)…")
                            .foregroundStyle(.secondary)
                    }.padding(Spacing.lg)
                }
            }
            SettingsGroup("Your collection") {
                SettingsValueRow(title: "Songs", icon: "music.note") { Text("\(library.songs.count)").monospacedDigit() }
                SettingsValueRow(title: "Albums", icon: "square.stack") { Text("\(library.albums.count)").monospacedDigit() }
                SettingsValueRow(title: "Artists", icon: "person.2") { Text("\(library.artists.count)").monospacedDigit() }
            }
        }
        .navigationTitle("Music Library")
    }
}

private struct MetadataSettingsView: View {
    var body: some View {
        SettingsPage {
            SettingsGroup("Tags & cover art") {
                SettingsLink("Auto Fix Tags", subtitle: "Correct tags and fill in missing details", icon: "wand.and.stars", tool: .autoFixTags)
                SettingsLink("Artwork Fetcher", subtitle: "Find album covers or change artist photos", icon: "photo.on.rectangle.angled", tool: .artworkFetcher)
                // The tool exists only in the animated-art branch; never offer a dead destination.
                if let motion = Tool(rawValue: "animatedArtwork"), Tool.available.contains(motion) {
                    SettingsLink(motion.label, subtitle: "Manage your downloaded album covers", icon: motion.icon, tool: motion)
                }
            }
            Text("Metadata and artwork searches use keyless iTunes Search, MusicBrainz, Deezer, Wikidata and Wikimedia Commons. No API keys are needed.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .navigationTitle("Metadata & Artwork")
    }
}

private struct AboutSettingsView: View {
    @State private var showingIntroduction = false
    var body: some View {
        SettingsPage {
            SettingsGroup("amp") {
                HStack(spacing: Spacing.lg) {
                    Image("AmpLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("amp").font(.title3.weight(.semibold))
                        Text("Your music, on your iPhone.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, Spacing.sm)
                }.padding(Spacing.lg).frame(maxWidth: .infinity, alignment: .leading)
                LabeledContent("Version", value: AppBuildVersion.version(in: Bundle.main.infoDictionary ?? [:])).padding(Spacing.lg)
                LabeledContent("Build", value: AppBuildVersion.build(in: Bundle.main.infoDictionary ?? [:])).padding(Spacing.lg)
                LabeledContent("Release", value: Bundle.main.infoDictionary?["ErhuReleaseTag"] as? String ?? "Development").padding(Spacing.lg)
                Text("amp plays your local music with full-screen artwork, playlists, synced lyrics, an equalizer, Transition Studio and Home Screen widgets.")
                    .font(.footnote).foregroundStyle(.secondary).padding([.horizontal, .bottom], Spacing.lg)
            }
            PlayerWidgetStatusSettings()
            SettingsGroup("Privacy") {
                Label("Music stays on your iPhone", systemImage: "iphone").padding(Spacing.lg)
                Text("Your music files and library index stay on this device. Online lyrics, metadata and artwork searches use the song or artist details needed for the request.")
                    .font(.footnote).foregroundStyle(.secondary).padding([.horizontal, .bottom], Spacing.lg)
            }
            SettingsGroup("Project") {
                NavigationLink { ImageCreditsView() } label: {
                    SettingsActionLabel(title: "Image credits", icon: "photo.on.rectangle")
                }
                Divider().padding(.leading, Spacing.lg)
                Button { showingIntroduction = true } label: {
                    SettingsActionLabel(title: "Introduction & tool guide", icon: "book.closed")
                }
                Divider().padding(.leading, Spacing.lg)
                Link(destination: URL(string: "https://github.com/SRJW/Erhu-iOS-powerampp")!) {
                    SettingsActionLabel(title: "Source code on GitHub", icon: "chevron.left.forwardslash.chevron.right", accessory: "arrow.up.right")
                }
            }
            SettingsGroup("amp project") {
                Link(destination: URL(string: "https://github.com/SRJW/amp/releases")!) {
                    SettingsActionLabel(title: "Download amp releases", icon: "shippingbox", accessory: "arrow.up.right")
                }
                Link(destination: URL(string: "https://github.com/SRJW/Erhu-iOS-powerampp/issues")!) {
                    SettingsActionLabel(title: "Report an amp issue", icon: "bubble.left", accessory: "arrow.up.right")
                }
                Text("amp is maintained in SRJW/Erhu-iOS-powerampp. Based on Erhu for iOS by Mohammed Azeemulla Khan, with original Android contributions by Lochan Thakke and Kshitij Kekunnaya. Original licences and image credits remain applicable.")
                    .font(.footnote).foregroundStyle(.secondary).padding(Spacing.lg)
            }
            SettingsGroup("Updates") { ReleaseCheckView() }
        }
        .navigationTitle("About amp")
        .sheet(isPresented: $showingIntroduction) { IntroductionView() }
    }
}

private struct PlayerWidgetStatusSettings: View {
    @Environment(PlayerController.self) private var player
    @State private var sharedTitle = ""
    @State private var error: String?

    var body: some View {
        SettingsGroup("Home Screen widget") {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                if let storage = PlayerWidgetStorage.shared {
                    Label("Shared storage available", systemImage: "checkmark.circle")
                    Text("Last shared song: \(sharedTitle)").font(.subheadline)
                    Text(storage.group).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                } else {
                    Label("Shared storage unavailable", systemImage: "exclamationmark.triangle")
                    Text("When signing in FlareStore, preserve the widget extension and a matching App Group for both targets. Without that permission, iOS prevents the widget from reading the current song.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if let error { Text(error).font(.caption).foregroundStyle(.secondary) }
                Button("Refresh widget") {
                    player.refreshSystemPlayback()
                    readStatus()
                }.buttonStyle(.bordered)
            }.padding(Spacing.lg)
        }
        .onAppear { readStatus() }
    }

    private func readStatus() {
        sharedTitle = PlayerWidgetSnapshot.load().title
        error = PlayerWidgetPublisher.lastError
    }
}


struct PlaybackSettingsView: View {
    @Environment(TransitionSettingsStore.self) private var transitions
    @AppStorage(PlaybackPreferences.waveformKey) private var waveformMode = PlaybackPreferences.defaultWaveform

    private var crossfade: Binding<Double> {
        Binding(get: {
            transitions.config.global.masterEnabled
                ? Double(transitions.config.global.defaultChoice.specOrNil?.durationMs ?? 0) / 1000 : 0
        }, set: { seconds in
            var global = transitions.config.global
            if seconds == 0 {
                global.defaultChoice = .off
                if global.manualMode == .custom { global.manualMode = .off }
            } else {
                var spec = global.defaultChoice.specOrNil ?? TransitionSpec()
                spec.durationMs = Int(seconds * 1000)
                global.defaultChoice = .custom(spec)
                global.masterEnabled = true
            }
            transitions.setGlobal(global)
        })
    }

    var body: some View {
        SettingsPage {
            SettingsGroup("Crossfade") {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Picker("Automatic song changes", selection: Binding(
                        get: { transitions.config.global.automaticMode ?? .all },
                        set: { mode in var global = transitions.config.global; global.automaticMode = mode; transitions.setGlobal(global) })) {
                        ForEach(AutomaticCrossfadeMode.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    Picker("Manual song changes", selection: Binding(
                        get: { transitions.config.global.manualMode ?? (transitions.config.global.defaultChoice.specOrNil == nil ? .off : .custom) },
                        set: { mode in
                            var global = transitions.config.global
                            global.manualMode = mode
                            if mode == .custom, global.defaultChoice.specOrNil == nil {
                                if global.automaticMode == nil { global.automaticMode = .off }
                                global.defaultChoice = .custom(TransitionSpec())
                            }
                            if mode != .off { global.masterEnabled = true }
                            transitions.setGlobal(global)
                        })) {
                        ForEach(ManualCrossfadeMode.allCases.filter { $0 != .linked }, id: \.self) { Text($0.label).tag($0) }
                    }
                    Text("Crossfade length").font(.subheadline.weight(.semibold))
                    Text(crossfade.wrappedValue == 0 ? "Off" : String(format: "%.1f seconds", crossfade.wrappedValue))
                        .monospacedDigit()
                    Slider(value: crossfade, in: 0...max(PlaybackPreferences.crossfadeRange.upperBound, crossfade.wrappedValue), step: PlaybackPreferences.crossfadeStep)
                        .accessibilityLabel("Crossfade duration")
                        .accessibilityIdentifier("crossfadeDuration")
                    if transitions.config.global.manualMode == .short {
                        LabeledContent("Short manual crossfade", value: "\(transitions.config.global.shortManualDurationMs ?? 500) ms")
                        Slider(value: Binding(
                            get: { Double(transitions.config.global.shortManualDurationMs ?? 500) },
                            set: { duration in
                                var global = transitions.config.global
                                global.shortManualDurationMs = Int(duration)
                                transitions.setGlobal(global)
                            }), in: 500...2_000, step: 100)
                            .accessibilityLabel("Short manual crossfade duration")
                    }
                    Text("Automatic and manual changes can fade independently. Album and playlist transition overrides are kept. Paused changes stay paused.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Restore crossfade defaults") { transitions.setGlobal(GlobalTransitionSettings()) }
                        .frame(minHeight: 44)
                }.padding(Spacing.lg)
            }
            SettingsGroup("Waveform") {
                Picker("Mode", selection: $waveformMode) {
                    ForEach(PlayerWaveformMode.allCases) { mode in Text(mode.label).tag(mode.rawValue) }
                }
                .pickerStyle(.inline)
                .padding(Spacing.lg)
                .accessibilityIdentifier("waveformMode")
            }
        }
        .navigationTitle("Playback")
    }
}

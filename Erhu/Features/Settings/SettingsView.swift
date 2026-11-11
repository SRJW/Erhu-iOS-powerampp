import SwiftUI
import UniformTypeIdentifiers

enum SettingsPageRoute: String, Hashable { case appearance, visualizer, library, metadata, about }

struct SettingsDestinationView: View {
    let page: SettingsPageRoute
    var body: some View {
        Group {
            switch page {
            case .appearance: AppearanceSettingsView()
            case .visualizer: VisualizerSettingsView()
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
                SettingsLink("Audio & Equalizer", subtitle: "8-band equalizer, presets and audio effects", icon: "chart.bar.fill", tool: .equalizer)
                SettingsLink("Visualizer", subtitle: "Style and feel of the Now Playing visualizer", icon: "waveform", page: .visualizer)
            }
            SettingsGroup("Library") {
                Toggle("Show VYBE and radio discovery", isOn: $settings.vybeEnabled).padding(Spacing.lg)
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
                .padding(.bottom, Spacing.lg)
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
                    Image("ErhuLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 56, height: 56)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("amp").font(.title3.weight(.semibold))
                        Text("Your music, on your iPhone.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, Spacing.sm)
                }.padding(Spacing.lg).frame(maxWidth: .infinity, alignment: .leading)
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–").padding(Spacing.lg)
                LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "–").padding(Spacing.lg)
            }
            SettingsGroup("Privacy") {
                Label("Music stays on your iPhone", systemImage: "iphone").padding(Spacing.lg)
                Text("Your music files, library index and VYBE processing stay on this device. Online lyrics, metadata and artwork searches use the song or artist details needed for the request.")
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
            #if !ERHU_APP_STORE
            // External donation links are fine for sideloaded builds. An App Store build must
            // hide this (guideline 3.1.1) and offer an In-App Purchase tip jar instead.
            SettingsGroup("Support") {
                Link(destination: URL(string: "https://ko-fi.com/erhu")!) {
                    SettingsActionLabel(title: "Support erhu on Ko-fi", icon: "cup.and.saucer.fill", accessory: "arrow.up.right")
                }
                Text("amp is free. If you'd like to help get it onto the App Store, you can buy me a coffee.")
                    .font(.footnote).foregroundStyle(.secondary).padding([.horizontal, .bottom], Spacing.lg)
            }
            #endif
            SettingsGroup("Updates") { ReleaseCheckView() }
        }
        .navigationTitle("About amp")
        .sheet(isPresented: $showingIntroduction) { IntroductionView() }
    }
}

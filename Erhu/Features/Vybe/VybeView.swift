import SwiftUI

/// VYBE: find music in the library by mood, genre, tempo or artist, on this phone.
struct VybeView: View {
    @Environment(VybeStore.self) private var vybe
    @Environment(PlayerController.self) private var player
    @Environment(AppRouter.self) private var router
    @Environment(\.palette) private var palette
    @State private var text = ""
    @FocusState private var focused: Bool

    private static let suggestions = [
        "Dark, atmospheric hip-hop", "High-energy music for the gym", "Chill R&B, no rap",
        "Mellow tracks under 100 BPM", "Music from the 90s", "Sad, soulful music",
    ]

    var body: some View {
        LibraryRootScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.md) {
                Text("Describe a mood, a sound, or what you're doing. Find the right music in your library, offline.")
                    .font(.subheadline)
                    .foregroundStyle(palette.onSurfaceVariant)
                field
                if text.isBlank {
                    RecentSearchesView(scope: "vybe") { text = $0; submit() }
                }
                if router.section == .vybe { status }
                switch vybe.query {
                case .idle:
                    suggestionChips
                case .searching(let label):
                    HStack(spacing: Spacing.sm) {
                        ProgressView()
                        Text("Searching on this phone… \(label)").font(.subheadline).foregroundStyle(palette.onSurfaceVariant)
                    }
                case .error(_, let message):
                    Text("Couldn't search: \(message)").font(.subheadline).foregroundStyle(.red)
                case .done(_, let results):
                    resultsView(results)
                }
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.vertical, Spacing.sm)
        }
        .tracksLibraryScrolling()
        .scrollDismissesKeyboard(.interactively)
        // All section stacks remain mounted. Appearance alone does not mean this tab is shown.
        .onAppear { if router.section == .vybe { vybe.start() } }
        .onChange(of: router.section) { _, section in if section == .vybe { vybe.start() } }
    }

    private var field: some View {
        HStack(spacing: Spacing.sm) {
            VybeCassetteIcon().foregroundStyle(palette.onSurfaceVariant)
            TextField("Describe what you want to hear", text: $text)
                .focused($focused)
                .submitLabel(.search)
                .onSubmit(submit)
            if !text.isEmpty {
                Button {
                    SearchHistoryStore.shared.remember(text, in: "vybe")
                    text = ""
                    vybe.clear()
                } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(palette.onSurfaceVariant) }
                .accessibilityLabel("Clear")
                Button(action: submit) { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                    .accessibilityLabel("Search your library")
            }
        }
        .padding(.horizontal, Spacing.md)
        .frame(height: 48)
        .background(RoundedRectangle(cornerRadius: Radius.large, style: .continuous).fill(palette.surfaceVariant.opacity(0.6)))
    }

    private func submit() {
        focused = false
        SearchHistoryStore.shared.remember(text, in: "vybe")
        vybe.submit(text)
    }

    @ViewBuilder private var status: some View {
        switch vybe.status {
        case .loadingModel:
            progress("Getting VYBE ready…", nil)
        case .indexing(let done, let total):
            progress("Learning your library · \(done) of \(total) songs", Double(done) / Double(max(total, 1)))
        case .ready(let songs):
            Text("\(songs) songs · Offline search")
                .font(.caption)
                .foregroundStyle(palette.onSurfaceVariant)
        case .failed(let message):
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(message).font(.subheadline).foregroundStyle(.red)
                Button("Try again") { Task { await vybe.engine.refresh() } }.buttonStyle(.bordered)
            }
        }
    }

    private func progress(_ label: String, _ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(label).font(.caption).foregroundStyle(palette.onSurfaceVariant)
            if let value { ProgressView(value: value) } else { ProgressView().progressViewStyle(.linear) }
        }
    }

    private var suggestionChips: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Try").font(.headline)
            if let current = player.state.currentSong {
                chip("Like \"\(current.title)\"", systemImage: "waveform") { focused = false; vybe.similarToCurrent() }
            }
            ForEach(Self.suggestions, id: \.self) { suggestion in
                chip(suggestion, systemImage: nil) {
                    text = suggestion
                    submit()
                }
            }
        }
    }

    private func chip(_ label: String, systemImage: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                if let systemImage { Image(systemName: systemImage) }
                Text(label).lineLimit(1)
            }
            .font(.subheadline)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(Capsule().strokeBorder(palette.outline))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func resultsView(_ results: VybeResults) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(results.title).font(.headline)
            if let note = results.note { Text(note).font(.caption).foregroundStyle(palette.onSurfaceVariant) }
            ForEach(results.matchedReferences) { match in
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(palette.primary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(match.name).font(.subheadline.weight(.semibold))
                        Text(match.detail).font(.caption).foregroundStyle(palette.onSurfaceVariant)
                    }
                }.padding(.vertical, Spacing.xs)
            }
            ForEach(results.choices) { choice in
                Button { focused = false; vybe.choose(choice) } label: {
                    HStack(spacing: Spacing.md) {
                        Image(systemName: choice.match.symbol).frame(width: 24)
                        VStack(alignment: .leading, spacing: 3) {
                            if let context = choice.context { Text("For \"\(context)\"").font(.caption).foregroundStyle(palette.onSurfaceVariant) }
                            Text(choice.match.name).font(.body.weight(.semibold))
                            Text(choice.match.detail).font(.caption).foregroundStyle(palette.onSurfaceVariant)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption)
                    }
                    .padding(Spacing.md).frame(maxWidth: .infinity, alignment: .leading)
                    .background(palette.surfaceVariant.opacity(0.6), in: RoundedRectangle(cornerRadius: Radius.large))
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            if results.choices.isEmpty && !results.songs.isEmpty {
                HStack(spacing: Spacing.sm) {
                    Button { vybe.play(results.songs, index: 0) } label: { Label("Play \(results.songs.count)", systemImage: "play.fill").foregroundStyle(palette.onFilledButton) }
                        .modifier(PaletteFilledButton())
                    Button { vybe.shuffle(results.songs) } label: { Image(systemName: "shuffle") }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Shuffle")
                    Button { vybe.addAllToQueue(results.songs) } label: { Image(systemName: "text.badge.plus") }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Add all to queue")
                }
                .disabled(results.songs.isEmpty)
                .padding(.vertical, Spacing.xs)
            }
        }
        if results.songs.isEmpty && results.choices.isEmpty && results.showsEmptySuggestion {
            Text("No matches in your library. Try a broader style or fewer filters.").foregroundStyle(palette.onSurfaceVariant)
        }
        ForEach(Array(results.songs.enumerated()), id: \.element.id) { index, result in
            Button { vybe.play(results.songs, index: index) } label: {
                HStack(spacing: Spacing.md) {
                    SongArtworkView(song: result.song, maxPixels: 144)
                        .frame(width: ArtworkSize.list, height: ArtworkSize.list)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.song.title).font(.body.weight(.semibold)).lineLimit(1)
                            .foregroundStyle(result.song.id == player.state.currentSong?.id ? Color.accentColor : palette.onSurface)
                        Text("\(result.song.artist) • \(result.song.album)").font(.caption).foregroundStyle(palette.onSurfaceVariant).lineLimit(1)
                        if !result.reasons.isEmpty {
                            Text(result.reasons.joined(separator: " · ")).font(.caption2).foregroundStyle(palette.onSurfaceVariant).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

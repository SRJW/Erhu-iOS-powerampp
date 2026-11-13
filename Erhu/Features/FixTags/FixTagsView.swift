import SwiftUI

/// Auto Fix Tags: a queue of tracks, the fields to fix and the source, Start / Pause, each track's
/// outcome with what was looked up, and Revert for the tracks that were changed.
struct FixTagsView: View {
    @Environment(FixTagsStore.self) private var store
    @Environment(LibraryStore.self) private var library
    @Environment(\.palette) private var palette
    @State private var addingSongs = false
    @State private var selectedForRevert = Set<Int64>()
    @State private var detail: RepairItem?
    @State private var confirmingClear = false

    var body: some View {
        List {
            optionsSection
            statusSection
            queueSection
        }.modifier(ToolPageAppearance())
        .navigationTitle("Fix tags")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { store.autoSelectBestCandidates() } label: {
                        Label("Auto-fill best available tags (\(store.autoCandidateCount))", systemImage: "wand.and.stars")
                    }
                    .disabled(store.isRunning || store.isCheckingMissing || store.autoCandidateCount == 0)
                    Button { addingSongs = true } label: { Label("Add songs", systemImage: "plus") }
                        .disabled(store.isRunning || store.isCheckingMissing)
                    if !store.revertible.isEmpty {
                        Button {
                            Task { await store.revert(selectedForRevert.isEmpty ? Set(store.revertible.map(\.id)) : selectedForRevert) }
                            selectedForRevert = []
                        } label: {
                            Label(selectedForRevert.isEmpty ? "Revert all changes" : "Revert \(selectedForRevert.count)", systemImage: "arrow.uturn.backward")
                        }
                        .disabled(store.isRunning || store.isCheckingMissing)
                    }
                    Button(role: .destructive) { confirmingClear = true } label: { Label("Clear queue", systemImage: "trash") }
                        .disabled(store.isRunning || store.isCheckingMissing || store.queue.isEmpty)
                } label: { Image(systemName: "ellipsis.circle") }
                .accessibilityLabel("Queue options")
            }
        }
        .sheet(isPresented: $addingSongs) { AddSongsSheet { store.enqueue($0) } }
        .sheet(item: $detail) { item in RepairItemDetail(item: item) }
        .confirmationDialog("Clear the queue?", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("Clear", role: .destructive) {
                store.clear()
                selectedForRevert = []
            }
        } message: {
            Text("The kept originals are deleted too, so the changes can no longer be reverted.")
        }
    }

    private var optionsSection: some View {
        Section {
            ForEach(MetadataField.allCases.filter { $0 != .filename }) { field in
                Toggle(field.displayName, isOn: Binding(get: { store.selectedFields.contains(field) }, set: { store.setField(field, $0) }))
                    .disabled(store.isRunning || store.isCheckingMissing)
            }
            Picker("Source", selection: Binding(get: { store.settings.source }, set: { value in store.update { $0.source = value } })) {
                ForEach(MetadataSources.options, id: \.key) { Text($0.label).tag($0.key) }
            }
            .disabled(store.isRunning || store.isCheckingMissing)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Write a match from \(Int((store.settings.acceptAt * 100).rounded())) % confidence")
                Slider(value: Binding(get: { Double(store.settings.acceptAt) }, set: { value in store.update { $0.acceptAt = Float(value) } }),
                       in: 0.7...0.99, step: 0.01)
            }
            .disabled(store.isRunning || store.isCheckingMissing)
        } header: {
            Text("What to fix")
        } footer: {
            Text(FieldSelection(store.selectedFields).fillOnly
                ? "All fields: the title is corrected; existing album, artist and other valid tags stay. Missing track and disc numbers come from the matched album's tracklist. Album pages sort by disc, then track."
                : "Selected fields replace the file's tags. Track and disc numbers must belong to the same album edition; unknown positions are left alone. BPM estimates never replace a tagged tempo.")
        }.toolSectionAppearance()
    }

    private var statusSection: some View {
        Section {
            if store.isRunning {
                HStack {
                    ProgressView()
                    if let progress = store.autoSelectionProgress {
                        Text("Filling best available tags · \(progress.completed)/\(progress.total)").lineLimit(1)
                    } else {
                        Text("Looking up \(store.queue.filter { $0.status == .fixing }.first?.song.title ?? "")…").lineLimit(1)
                    }
                    Spacer()
                    Button("Pause") { store.pause() }
                }
            } else {
                Button {
                    Task { await store.findMissingTags() }
                } label: {
                    Label(store.hasMissingScanProgress ? "Continue checking missing tags" : "Find tracks with missing tags", systemImage: "wand.and.stars")
                }
                Button { addingSongs = true } label: { Label("Add songs…", systemImage: "plus") }
                Button {
                    store.start()
                } label: {
                    Label(store.hasSavedProgress ? "Continue fixing tags" : "Start", systemImage: "play.fill")
                }
                .disabled(!store.hasWork || store.isCheckingMissing)
                if store.autoCandidateCount > 0 {
                    Button { store.autoSelectBestCandidates() } label: {
                        Label(store.isAutoSelectionPaused ? "Continue filling best available tags" : "Auto-fill best available tags", systemImage: "wand.and.stars")
                    }
                    .disabled(store.isCheckingMissing)
                    Text("Checks available sources for each selected missing field. Saves a song only when all selected tags are complete. Unresolved songs stay unchanged for review. Originals remain available for Revert.")
                        .font(.footnote).foregroundStyle(palette.onSurfaceVariant)
                } else if !store.hasWork {
                    Text(store.queue.isEmpty ? "Add songs or find the ones with missing tags first." : "Nothing left to fix in the queue.")
                        .font(.footnote).foregroundStyle(palette.onSurfaceVariant)
                }
                if store.hasMissingScanProgress, !store.isCheckingMissing, let progress = store.missingScanProgress {
                    Text("Saved check: \(progress.completed) of \(progress.total) files").font(.caption)
                }
                if store.isCheckingMissing {
                    if let progress = store.missingScanProgress {
                        ProgressView(value: Double(progress.completed), total: Double(max(progress.total, 1)))
                        Text("Checked \(progress.completed) of \(progress.total) files").font(.caption)
                    }
                    Button("Stop checking", role: .cancel) { store.stopMissingScan() }
                }
                if let message = store.missingScanMessage { Text(message).font(.footnote).foregroundStyle(palette.onSurfaceVariant) }
            }
            if let reason = store.pauseReason {
                Text(reason).font(.footnote).foregroundStyle(palette.onSurfaceVariant)
            }
            if let message = store.autoSelectionMessage {
                Text(message).font(.footnote).foregroundStyle(palette.onSurfaceVariant)
            }
            if !store.queue.isEmpty {
                Text(summary).font(.footnote).foregroundStyle(palette.onSurfaceVariant)
            }
        } footer: {
            Text("Automatic mode combines verified iTunes, MusicBrainz and Deezer matches for different fields. Deezer is optional where available; a single-source choice restricts catalogue matching. MusicBrainz supplies recording and album genres, with catalogue genres and linked Wikidata genres as fallbacks. Repairs are saved only when every selected tag is complete. Missing-tag checks cover every selected field. Your music is never uploaded. Each changed file's original is kept until you clear the queue, so it can be reverted.")
        }.toolSectionAppearance()
    }

    private var summary: String {
        let counts = Dictionary(grouping: store.queue, by: { $0.status == .partial ? RepairStatus.needsReview : $0.status }).mapValues(\.count)
        let order: [RepairStatus] = [.done, .unchanged, .needsReview, .noMatch, .failed, .networkFailed, .reverted, .pending]
        return order.compactMap { status in counts[status].map { "\($0) \(status.label.lowercased())" } }.joined(separator: " · ")
    }

    private var queueSection: some View {
        Section("Queue") {
            if store.queue.isEmpty {
                Text("Add songs here, or choose \"Fix tags online\" in any song's menu.")
                    .font(.footnote).foregroundStyle(palette.onSurfaceVariant)
            }
            ForEach(store.queue) { item in
                HStack(spacing: Spacing.md) {
                    if item.backup != nil {
                        Button {
                            if selectedForRevert.contains(item.id) { selectedForRevert.remove(item.id) } else { selectedForRevert.insert(item.id) }
                        } label: {
                            Image(systemName: selectedForRevert.contains(item.id) ? "checkmark.circle.fill" : "circle")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(selectedForRevert.contains(item.id) ? "Selected for revert" : "Select for revert")
                    }
                    Button { detail = item } label: { RepairRow(item: item) }
                        .buttonStyle(.plain)
                }
                .swipeActions {
                    if !store.isRunning {
                        Button(role: .destructive) { store.remove(item) } label: { Label("Remove", systemImage: "trash") }
                        if item.status != .pending && item.status != .fixing {
                            Button { store.retry(item) } label: { Label("Retry", systemImage: "arrow.clockwise") }.tint(.blue)
                        }
                    }
                }
            }
        }.toolSectionAppearance()
    }
}

private struct RepairRow: View {
    let item: RepairItem
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: Spacing.md) {
            SongArtworkView(song: item.song, maxPixels: 120)
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.song.title).lineLimit(1)
                if item.status != .pending && item.status != .fixing {
                    Text(item.status.label).font(.caption.weight(.semibold))
                        .foregroundStyle(item.status == .partial || item.status == .needsReview ? Color.orange : palette.onSurfaceVariant)
                }
                Text(item.song.subtitle).font(.caption).foregroundStyle(palette.onSurfaceVariant).lineLimit(1)
                if let reason = item.reason ?? item.changes.first.map({ "\($0.field.displayName): \($0.newValue)" }) {
                    Text(reason).font(.caption2).foregroundStyle(palette.onSurfaceVariant).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            StatusBadge(status: item.status)
        }
        .contentShape(Rectangle())
    }
}

private struct StatusBadge: View {
    let status: RepairStatus

    var body: some View {
        if status == .fixing {
            ProgressView()
        } else {
            Image(systemName: icon).foregroundStyle(color).accessibilityLabel(status.label)
        }
    }

    private var icon: String {
        switch status {
        case .pending: "clock"
        case .fixing: "hourglass"
        case .done: "checkmark.circle.fill"
        case .partial: "exclamationmark.circle"
        case .unchanged: "equal.circle"
        case .needsReview: "questionmark.circle"
        case .noMatch: "magnifyingglass"
        case .failed: "exclamationmark.triangle"
        case .networkFailed: "wifi.exclamationmark"
        case .reverted: "arrow.uturn.backward.circle"
        }
    }

    private var color: Color {
        switch status {
        case .done: .green
        case .partial: .orange
        case .failed, .networkFailed: .red
        case .needsReview: .orange
        default: .secondary
        }
    }
}

/// What one lookup saw: the track's identity, each query and every provider's answer, the best
/// candidates and the changes made (or why none were).
struct RepairItemDetail: View {
    private var currentItem: RepairItem { store.queue.first { $0.id == item.id } ?? item }
    private var canChoose: Bool { BulkMetadataSelection.canResolve(currentItem) }

    let item: RepairItem
    @Environment(FixTagsStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var choice: MetadataCandidate?
    @State private var editingManually = false

    var body: some View {
        let item = currentItem
        NavigationStack {
            List {
                Section("Result") {
                    LabeledContent("Status", value: item.status.label)
                    if let reason = item.reason { Text(reason).font(.footnote) }
                    if canChoose {
                        Button { editingManually = true } label: {
                            Label("Enter remaining tags manually", systemImage: "square.and.pencil")
                        }
                        .disabled(store.isRunning || store.isCheckingMissing)
                        Text("Complete the remaining selected tags to save the whole repair together. Unknown fields keep this song in Needs review.")
                            .font(.footnote).foregroundStyle(.secondary)
                        if store.isRunning {
                            Button("Pause repairs to edit") { store.pause() }
                            Text("Editing becomes available after the current song finishes.").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }.toolSectionAppearance()
                if !item.changes.isEmpty {
                    Section(item.proposedRequest == nil ? "Changes" : "Suggested changes · not saved") {
                        ForEach(Array(item.changes.enumerated()), id: \.offset) { _, change in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(change.field.displayName).font(.caption.weight(.semibold))
                                Text("\(change.oldValue ?? "—") → \(change.newValue)").font(.footnote)
                            }
                        }
                    }.toolSectionAppearance()
                }
                if !item.notes.isEmpty {
                    Section("Lookup details") {
                        ForEach(item.notes, id: \.self) { Text($0).font(.footnote) }
                    }.toolSectionAppearance()
                }
                if let diagnostics = item.diagnostics {
                    Section("The file") {
                        LabeledContent("File", value: diagnostics.fileName)
                        LabeledContent("Title", value: diagnostics.identity.title ?? "—")
                        LabeledContent("Artist", value: diagnostics.identity.artist ?? diagnostics.identity.fileArtist ?? "—")
                        LabeledContent("Album", value: diagnostics.identity.album ?? "—")
                        if !diagnostics.identity.fileTitles.isEmpty {
                            LabeledContent("From the file name", value: diagnostics.identity.fileTitles.joined(separator: " · "))
                        }
                    }.toolSectionAppearance()
                    ForEach(Array(diagnostics.attempts.enumerated()), id: \.offset) { index, attempt in
                        Section("Search \(index + 1) (\(attempt.source))") {
                            Text([attempt.title, attempt.artist, attempt.album.map { "album: \($0)" }].compactMap { $0 }.joined(separator: " · "))
                                .font(.footnote)
                            ForEach(Array(attempt.outcomes.enumerated()), id: \.offset) { _, outcome in
                                LabeledContent(outcome.providerName) {
                                    Text(outcome.candidateCount > 0 ? "\(outcome.candidateCount) · \(outcome.status.label)" : outcome.errorMessage ?? outcome.status.label)
                                        .font(.caption)
                                }
                            }
                        }.toolSectionAppearance()
                    }
                    if !diagnostics.topCandidates.isEmpty {
                        Section {
                            ForEach(diagnostics.topCandidates) { candidate in
                                if canChoose {
                                    Button { choice = candidate } label: {
                                        HStack {
                                            Text(TrackMatcher.describe(candidate, diagnostics.identity)).font(.footnote).foregroundStyle(.primary)
                                            Spacer()
                                            Text("Use").font(.footnote.weight(.semibold))
                                        }
                                    }
                                    .disabled(store.isRunning || store.isCheckingMissing)
                                } else {
                                    Text(TrackMatcher.describe(candidate, diagnostics.identity)).font(.footnote)
                                }
                            }
                        } header: {
                            Text("Best candidates")
                        } footer: {
                            if canChoose { Text("Pick the right one to write it, with the fields chosen on the Fix tags page. The original is kept for Revert.") }
                        }.toolSectionAppearance()
                    }
                }
            }.modifier(ToolPageAppearance())
            .sheet(isPresented: $editingManually) {
                EditTagsSheet(song: item.song, queueItemID: item.id,
                              requestedFields: item.proposedFields.isEmpty ? store.selectedFields : item.proposedFields,
                              proposedRequest: item.proposedRequest)
            }
            .confirmationDialog("Write this match?", isPresented: Binding(get: { choice != nil }, set: { if !$0 { choice = nil } }),
                                titleVisibility: .visible, presenting: choice) { candidate in
                Button("Write \"\(candidate.title)\" by \(candidate.artist)") {
                    Task { await store.apply(candidate, to: item.id) }
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
            .navigationTitle(item.song.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}

/// Picks songs to add to the queue: search, select, or add everything shown.
private struct AddSongsSheet: View {
    let onAdd: ([Song]) -> Void
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selected = Set<Int64>()

    var body: some View {
        let shown = filtered
        NavigationStack {
            List(shown) { song in
                Button {
                    SearchHistoryStore.shared.remember(query, in: "add-songs")
                    if selected.contains(song.id) { selected.remove(song.id) } else { selected.insert(song.id) }
                } label: {
                    HStack {
                        Image(systemName: selected.contains(song.id) ? "checkmark.circle.fill" : "circle")
                        VStack(alignment: .leading) {
                            Text(song.title).lineLimit(1)
                            Text(song.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                .buttonStyle(.plain)
            }.modifier(ToolPageAppearance())
            .searchable(text: $query)
            .searchSuggestions {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ForEach(SearchHistoryStore.shared.entries("add-songs"), id: \.self) { Text($0).searchCompletion($0) }
                    if !SearchHistoryStore.shared.entries("add-songs").isEmpty {
                        Button("Clear history") { SearchHistoryStore.shared.clear("add-songs") }
                    }
                }
            }
            .onSubmit(of: .search) { SearchHistoryStore.shared.remember(query, in: "add-songs") }
            .onDisappear { SearchHistoryStore.shared.remember(query, in: "add-songs") }
            .navigationTitle("Add songs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(selected.isEmpty ? "Add all \(shown.count)" : "Add \(selected.count)") {
                        onAdd(selected.isEmpty ? shown : library.songs.filter { selected.contains($0.id) })
                        dismiss()
                    }
                    .disabled(shown.isEmpty && selected.isEmpty)
                }
            }
        }
    }

    private var filtered: [Song] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return library.songs }
        return library.songs.filter { song in
            let text = "\(song.title) \(song.artist) \(song.album)".lowercased()
            return words.allSatisfy { text.contains($0) }
        }
    }
}

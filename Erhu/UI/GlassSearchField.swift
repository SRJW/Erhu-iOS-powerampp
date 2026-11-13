import SwiftUI
import UIKit

/// The same floating search control in global search and section-local pull-down search.
struct GlassSearchField: View {
    @Environment(\.scenePhase) private var scenePhase
    @Binding var text: String
    let prompt: String
    @FocusState.Binding var focused: Bool
    let close: () -> Void
    var identifier = "librarySearchField"
    var historyScope = "library"

    var body: some View {
        HStack(spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(prompt, text: $text)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($focused).submitLabel(.search).onSubmit {
                        SearchHistoryStore.shared.remember(text, in: historyScope)
                        focused = false
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                    .accessibilityIdentifier(identifier)
                if !text.isEmpty {
                    Button { SearchHistoryStore.shared.remember(text, in: historyScope); text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        .frame(width: 44, height: 44).contentShape(Rectangle()) }
                        .buttonStyle(.plain).accessibilityLabel("Clear search")
                        .accessibilityIdentifier("searchClearButton")
                }
            }
            .padding(.horizontal, Spacing.md).frame(minHeight: 48)
            .background { Color.clear.glassSurface(cornerRadius: 28).allowsHitTesting(false) }
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.15)).allowsHitTesting(false))
            Button { SearchHistoryStore.shared.remember(text, in: historyScope); focused = false; close() } label: {
                Image(systemName: "xmark").font(.title3).frame(width: 48, height: 48)
            }.buttonStyle(.plain)
                .background { Color.clear.glassSurface(cornerRadius: 24).allowsHitTesting(false) }
                .contentShape(Circle())
                .accessibilityLabel("Close search")
                .accessibilityIdentifier("searchCloseButton")
        }
        .onChange(of: focused) { _, active in
            if !active { SearchHistoryStore.shared.remember(text, in: historyScope) }
        }
        .onDisappear { SearchHistoryStore.shared.remember(text, in: historyScope) }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active && focused { SearchHistoryStore.shared.remember(text, in: historyScope) }
        }
    }
}

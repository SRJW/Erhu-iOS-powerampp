import SwiftUI

struct RecentSearchesView: View {
    let scope: String
    let apply: (String) -> Void
    @State private var history = SearchHistoryStore.shared

    var body: some View {
        let entries = history.entries(scope)
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Recent searches").font(.headline)
                    Spacer()
                    Button("Clear") { history.clear(scope) }.buttonStyle(.plain).frame(minHeight: 44)
                }
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(entries, id: \.self) { query in
                            HStack(spacing: Spacing.sm) {
                                Button {
                                    history.remember(query, in: scope)
                                    apply(query)
                                } label: {
                                    Label(query, systemImage: "clock.arrow.circlepath")
                                        .lineLimit(1).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("recentSearch." + query)
                                Button { history.remove(query, in: scope) } label: {
                                    Image(systemName: "xmark").frame(width: 44, height: 44)
                                }.buttonStyle(.plain)
                                    .accessibilityLabel("Remove recent search: \(query)")
                            }
                        }
                    }
                }
                .frame(height: min(CGFloat(entries.count) * 44, 220))
                .scrollBounceBehavior(.basedOnSize)
            }.padding(.vertical, Spacing.sm)
        }
    }
}

import SwiftUI
import UIKit

/// The drawer occupies real scroll space: a downward pull reveals it below the title,
/// and an upward swipe slides it behind the title before the rest of the page scrolls.
struct LibraryBrowseScrollView<Controls: View, Content: View>: View {
    let title: String
    var isTabRoot = false
    var showsControls = true
    @Binding var query: String
    @Binding var showsSearch: Bool
    @ViewBuilder let controls: Controls
    @ViewBuilder let content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var searchFocused: Bool
    @ScaledMetric(relativeTo: .body) private var drawerHeight: CGFloat = 64
    @State private var drawer = SectionSearchDrawerState()

    var body: some View {
        GeometryReader { viewport in
            scroll(minimumHeight: viewport.size.height + drawerHeight)
                .opacity(drawer.ready ? 1 : 0)
        }
        .scrollBounceBehavior(.always)
        .scrollDismissesKeyboard(.interactively)
        .tracksLibraryScrolling()
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private func scroll(minimumHeight: CGFloat) -> some View {
        if isTabRoot {
            LibraryRootScrollView { pageContent(minimumHeight: minimumHeight) }
        } else {
            ScrollView { pageContent(minimumHeight: minimumHeight) }
        }
    }

    private func pageContent(minimumHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            LibraryBrowseHeader(title: title, showsControls: showsControls, query: $query,
                                focused: $searchFocused, drawer: drawer, height: drawerHeight,
                                close: closeSearch, reveal: revealSearch, controls: controls)
            if !drawer.collapsed && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                RecentSearchesView(scope: "browse." + title.lowercased()) { query = $0; searchFocused = true }
                    .padding(.horizontal, Spacing.gutter)
            }
            content
        }
        .frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .topLeading)
        .padding(.top, 8)
        .background {
            SectionSearchDrawerProbe(state: drawer, height: drawerHeight, initiallyRevealed: showsSearch,
                                     focused: { searchFocused }, reduceMotion: reduceMotion) { visible in
                showsSearch = visible
                if !visible, searchFocused {
                    searchFocused = false
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }.frame(width: 0, height: 0)
        }
    }

    private func closeSearch() {
        searchFocused = false
        query = ""
        drawer.setRevealed(false, animated: !reduceMotion)
    }

    private func revealSearch() {
        drawer.setRevealed(true, animated: !reduceMotion)
        searchFocused = true
    }
}

/// Only this small header reads the per-frame drawer position; the library results do not.
private struct LibraryBrowseHeader<Controls: View>: View {
    let title: String
    let showsControls: Bool
    @Binding var query: String
    @FocusState.Binding var focused: Bool
    let drawer: SectionSearchDrawerState
    let height: CGFloat
    let close: () -> Void
    let reveal: () -> Void
    let controls: Controls

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.largeTitle.bold())
                .padding(.horizontal, Spacing.gutter).padding(.bottom, 12)
                .offset(y: drawer.pinnedOffset).zIndex(1)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("sectionBrowseTitle")
            GlassSearchField(text: $query, prompt: "Search \(title.lowercased())", focused: $focused,
                             close: close, identifier: "sectionSearchField", historyScope: "browse." + title.lowercased())
                .padding(.horizontal, Spacing.gutter).padding(.vertical, 8)
                .frame(height: height)
                // Clip only the drawing. A content shape here is merged into the close button's
                // accessibility frame, so it spans the whole row and covers the text field: taps
                // and hit tests at the field land on "Close search" instead. The field is not
                // hittable while collapsed anyway, and partial states settle at once.
                .clipShape(SearchDrawerClip(hiddenHeight: drawer.pinnedOffset))
                .allowsHitTesting(!drawer.collapsed)
                .accessibilityHidden(drawer.collapsed)
            if showsControls {
                HStack(alignment: .top, spacing: 10) {
                    BrowseControlFlow { controls }
                    Button(action: reveal) {
                        Image(systemName: "magnifyingglass")
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .accessibilityLabel("Search \(title.lowercased())")
                    .accessibilityIdentifier("sectionSearchButton")
                    .opacity(drawer.collapsed ? 1 : 0)
                    .allowsHitTesting(drawer.collapsed)
                    .accessibilityHidden(!drawer.collapsed)
                }
                .padding(.horizontal, Spacing.gutter).padding(.vertical, 8)
            }
        }
    }
}

private struct SearchDrawerClip: Shape {
    var hiddenHeight: CGFloat
    var animatableData: CGFloat {
        get { hiddenHeight }
        set { hiddenHeight = newValue }
    }
    func path(in rect: CGRect) -> Path {
        let hidden = min(max(hiddenHeight, 0), rect.height)
        return Path(CGRect(x: rect.minX, y: rect.minY + hidden, width: rect.width, height: rect.height - hidden))
    }
}

/// Wrap filters on small phones and at large text sizes instead of hiding them offscreen.
private struct BrowseControlFlow: Layout {
    private let gap: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = max(proposal.width ?? 320, 1)
        let items = arrangement(width: width, subviews: subviews)
        return CGSize(width: width, height: items.map { $0.maxY }.max() ?? 0)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (index, frame) in arrangement(width: bounds.width, subviews: subviews).enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                                 proposal: ProposedViewSize(frame.size))
        }
    }
    private func arrangement(width: CGFloat, subviews: Subviews) -> [CGRect] {
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        return subviews.map { view in
            let ideal = view.sizeThatFits(.unspecified)
            let size = view.sizeThatFits(ProposedViewSize(width: min(ideal.width, width), height: nil))
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + gap; rowHeight = 0 }
            let frame = CGRect(x: x, y: y, width: size.width, height: size.height)
            x += size.width + gap; rowHeight = max(rowHeight, size.height)
            return frame
        }
    }
}

struct LibrarySortMenu: View {
    @Binding var selection: String
    let options: [LibrarySort]

    var body: some View {
        Menu {
            Picker("Sort by", selection: $selection) {
                ForEach(options, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
            }
        } label: {
            BrowseControlLabel(title: (LibrarySort(rawValue: selection) ?? .title).shortLabel, icon: "arrow.up.arrow.down")
        }
        .accessibilityLabel("Sort by \((LibrarySort(rawValue: selection) ?? .title).label)")
    }
}

struct BrowseControlLabel: View {
    let title: String
    let icon: String
    var selected = false

    var body: some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 12).frame(minHeight: 44)
            .foregroundStyle(.primary)
            .background(selected ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(selected ? 0.35 : 0.15)))
    }
}

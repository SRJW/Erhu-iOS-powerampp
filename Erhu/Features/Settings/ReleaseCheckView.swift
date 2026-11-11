import SwiftUI

struct ReleaseCheckView: View {
    @State private var checker = ReleaseChecker.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                switch checker.state {
                case .idle: Text("Check GitHub Releases for a newer build.")
                case .checking: ProgressView("Checking releases…")
                case .current:
                    Label("You have the latest published release for this variant", systemImage: "checkmark.circle")
                case .failed(let message): Text(message).foregroundStyle(.secondary)
                case .available(let release):
                    Label("\(release.tag_name) is available", systemImage: "arrow.down.circle").font(.headline)
                    if let notes = release.body?.nonBlank { Text(notes).font(.subheadline).lineLimit(8) }
                    Text("Install the IPA using SideStore or AltStore. amp cannot install itself.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.lg)
            if case .available(let release) = checker.state {
                Divider().padding(.leading, Spacing.lg)
                if let notes = release.body?.nonBlank {
                    Text(LocalizedStringKey(notes)).font(.footnote).padding(Spacing.lg)
                }
                Link(destination: release.html_url) {
                    SettingsActionLabel(title: "Release notes", icon: "doc.text", accessory: "arrow.up.right")
                }
                if let url = release.download(animated: BuildVariant.animated) {
                    Divider().padding(.leading, Spacing.lg)
                    Link(destination: url) {
                        SettingsActionLabel(title: "Download \(BuildVariant.animated ? "animated" : "static") IPA", icon: "arrow.down.circle", accessory: "arrow.up.right")
                    }
                }
            }
            Divider().padding(.leading, Spacing.lg)
            Button { Task { await checker.check(manual: true) } } label: {
                SettingsActionLabel(title: "Check for updates", icon: "arrow.clockwise")
            }.disabled(checker.state == .checking)
            Divider().padding(.leading, Spacing.lg)
            Link(destination: URL(string: "https://github.com/SRJW/Erhu-iOS-powerampp/releases")!) {
                SettingsActionLabel(title: "All releases", icon: "shippingbox", accessory: "arrow.up.right")
            }
            if let checkedAt = checker.checkedAt {
                Text("Last checked \(checkedAt.formatted())").font(.caption).foregroundStyle(.secondary)
                    .padding([.horizontal, .bottom], Spacing.lg)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

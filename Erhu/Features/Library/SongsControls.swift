import SwiftUI

private enum SongsControlSize {
    static let hero: CGFloat = 48
    static let tool: CGFloat = 44
    static let icon: CGFloat = 23
    static let gap: CGFloat = 4
}

struct SongsPlayButton: View {
    let title: String
    let symbol: String
    var filled = false
    let action: () -> Void
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.headline).lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: SongsControlSize.hero)
                .foregroundStyle(filled ? palette.onFilledButton : palette.onSurface)
                .background {
                    if filled { Capsule().fill(palette.filledButton).allowsHitTesting(false) }
                    else { Color.clear.glassSurface(cornerRadius: SongsControlSize.hero / 2).allowsHitTesting(false) }
                }
                .overlay(Capsule().strokeBorder(palette.outline).allowsHitTesting(false))
                .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .opacity(enabled ? 1 : 0.4)
    }
}

struct SongsToolLabel: View {
    let title: String
    let symbol: String
    var active = false
    @Environment(\.palette) private var palette
    var body: some View {
        VStack(spacing: SongsControlSize.gap) {
            Image(systemName: symbol)
                .font(.system(size: SongsControlSize.icon, weight: .semibold))
                .frame(width: SongsControlSize.tool, height: SongsControlSize.tool)
                .background { Color.clear.glassSurface(cornerRadius: SongsControlSize.tool / 2).allowsHitTesting(false) }
            Text(title).font(.caption).lineLimit(1)
        }
        .foregroundStyle(active ? palette.primary : palette.onSurface)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

struct SongsFilterLabel: View {
    let title: String
    let symbol: String
    @Environment(\.palette) private var palette
    var body: some View {
        HStack(spacing: SongsControlSize.gap) {
            Image(systemName: symbol)
            Text(title).lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "chevron.down").font(.caption2)
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background { Color.clear.glassSurface(cornerRadius: 22).allowsHitTesting(false) }
        .overlay(Capsule().strokeBorder(palette.outline).allowsHitTesting(false))
        .foregroundStyle(palette.onSurface)
    }
}

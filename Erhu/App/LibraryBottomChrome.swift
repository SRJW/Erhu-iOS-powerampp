import SwiftUI

extension View {
    /// Explicitly clip both material and content, including the mini player's progress line.
    func chromeSurface(enabled: Bool) -> some View {
        glassSurface(cornerRadius: 30, enabled: enabled)
            .clipShape(Capsule())
            .contentShape(Capsule())
    }
}

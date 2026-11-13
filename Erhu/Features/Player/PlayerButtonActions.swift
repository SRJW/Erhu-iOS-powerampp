import SwiftUI
import UIKit

/// Values for the requested player actions; transport and artwork keep their existing styling.
enum PlayerButtonConstants {
    static let titleFont = "AvenirNext-Bold"
    static let titleSize: CGFloat = 22
    static let subtitleFont = "AvenirNext-DemiBold"
    static let subtitleSize: CGFloat = 14
    static let metadataSeparator = " - "
    static let shareLabel = "Compartir"
    static let optionsLabel = "More options"
    static let settingsLabel = "Settings"
    static let locationUnavailable = "No se encontró la ubicación de esta canción."
    static let shareFailed = "No se pudo preparar el archivo para compartir."
    static let shareSymbol = "square.and.arrow.up"
    static let optionsSymbol = "ellipsis"
    static let iconSize: CGFloat = 25
    static let touchSize: CGFloat = 48
    static let iconOpacity = 0.5
    static let disabledOpacity = 0.3
    static let centerFraction: CGFloat = 0.5
    static let optionsRotation = 90.0
    static let highlightSeconds = 1.5
    static let revealDelaySeconds = 0.15
    static let highlightOpacity = 0.2
}

struct PlayerShareButton: View {
    let song: Song
    @Environment(LibraryActions.self) private var actions
    @State private var prepared: PreparedAudioShare?
    @State private var presenting = false
    @State private var preparing = false
    @State private var preparation: Task<Void, Never>?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let available = PreparedAudioShare.available(song.url) && !preparing
            Button { share() } label: {
                Image(systemName: PlayerButtonConstants.shareSymbol)
                    .font(.system(size: PlayerButtonConstants.iconSize, weight: .black))
                    .foregroundStyle(.white.opacity(PlayerButtonConstants.iconOpacity))
                    .frame(width: PlayerButtonConstants.touchSize, height: PlayerButtonConstants.touchSize)
                    .contentShape(Rectangle())
            }
            .disabled(!available)
            .opacity(available ? 1 : PlayerButtonConstants.disabledOpacity)
            .accessibilityLabel(PlayerButtonConstants.shareLabel)
            .accessibilityIdentifier("nowPlayingShare")
        }
        .sheet(isPresented: $presenting, onDismiss: cleanup) {
            if let prepared {
                AudioFileShareSheet(url: prepared.url) { presenting = false }
            }
        }
        .onDisappear { preparation?.cancel() }
    }

    private func share() {
        guard !preparing, PreparedAudioShare.available(song.url) else { return }
        preparing = true
        let source = song.url
        preparation = Task { @MainActor in
            defer { preparing = false }
            do {
                let copy = try await Task.detached(priority: .userInitiated) { try PreparedAudioShare.prepare(source) }.value
                guard !Task.isCancelled else { copy.remove(); return }
                prepared = copy
                presenting = true
            } catch {
                if !Task.isCancelled, PreparedAudioShare.available(source) {
                    actions.show(PlayerButtonConstants.shareFailed)
                }
            }
        }
    }

    private func cleanup() {
        prepared?.remove()
        prepared = nil
    }
}

private struct AudioFileShareSheet: UIViewControllerRepresentable {
    let url: URL
    let completed: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in completed() }
        return controller
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct PlayerTransportPressStyle: ButtonStyle {
    let reduceMotion: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? PlaybackPreferences.pressedScale : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.65), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

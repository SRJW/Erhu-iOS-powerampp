import SwiftUI
import UIKit
import AVFoundation

struct PlayerFullBleedBackground<Artwork: View>: View, Animatable {
    let palette: PlayerArtworkPalette
    var secondaryPalette: PlayerArtworkPalette? = nil
    var blend = 0.0
    @ViewBuilder var artwork: () -> Artwork

    var animatableData: Double {
        get { blend }
        set { blend = newValue }
    }

    private func background(_ palette: PlayerArtworkPalette) -> some View {
        LinearGradient(stops: [
            .init(color: Color(argb: palette.top), location: 0),
            .init(color: Color(argb: palette.top), location: PlayerReferenceStyle.coverHeightFraction),
            .init(color: Color(argb: palette.bottom), location: 1)
        ], startPoint: .top, endPoint: .bottom)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                background(palette)
                if let secondaryPalette {
                    let phase = min(max(blend, 0), 1)
                    let spread = PlayerReferenceStyle.paletteBlendSpread * sin(.pi * phase)
                    background(secondaryPalette)
                        .mask {
                            LinearGradient(colors: [
                                .white.opacity(min(phase + spread, 1)),
                                .white.opacity(max(phase - spread, 0))
                            ], startPoint: .top, endPoint: .bottom)
                        }
                }
                artwork()
                    .frame(width: geometry.size.width, height: geometry.size.height * PlayerReferenceStyle.coverHeightFraction)
                    .clipped()
                    .mask {
                        LinearGradient(stops: [.init(color: .white, location: 0),
                                               .init(color: .white, location: PlayerReferenceStyle.coverFadeStart),
                                               .init(color: .clear, location: 1)],
                                       startPoint: .top, endPoint: .bottom)
                    }
                LinearGradient(colors: [.black.opacity(PlayerReferenceStyle.statusScrimOpacity), .clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: PlayerReferenceStyle.statusScrimHeight)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct PlayerEqualizerGlyph: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            RoundedRectangle(cornerRadius: 3).frame(width: 8, height: 8)
            RoundedRectangle(cornerRadius: 3).frame(width: 8, height: 28)
            RoundedRectangle(cornerRadius: 3).frame(width: 8, height: 20)
        }.frame(width: 30, height: 30)
    }
}
struct PlayerQueueGlyph: View {
    var body: some View {
        VStack(spacing: 4) {
            ForEach(0..<3) { _ in Capsule().frame(width: 27, height: 6) }
        }.frame(width: 32, height: 32)
    }
}
private struct BluetoothGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height) }
        path.move(to: p(0.1, 0.25)); path.addLine(to: p(0.85, 0.75)); path.addLine(to: p(0.5, 1))
        path.addLine(to: p(0.5, 0)); path.addLine(to: p(0.85, 0.25)); path.addLine(to: p(0.1, 0.75))
        return path
    }
}
struct PlayerOutputBadge: View {
    let screenWidth: CGFloat
    @Environment(PlayerController.self) private var player
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let session = AVAudioSession.sharedInstance()
            let ports = session.currentRoute.outputs.map(\.portType)
            let bluetooth = ports.contains { [.bluetoothA2DP, .bluetoothHFP, .bluetoothLE].contains($0) }
            let symbol = ports.contains(.airPlay) ? "airplayaudio" : ports.contains(.headphones) ? "headphones" : ports.contains(.usbAudio) ? "cable.connector" : "speaker.wave.2.fill"
            let rate = session.sampleRate > 0 ? String(format: "%g", session.sampleRate / 1000) + "K" : "OUTPUT"
            // This is the engine's PCM format supplied to the session, not a claim
            // about Bluetooth codec resolution or the DAC's hardware bit depth.
            let bits = player.engine.outputPCMBitDepth
            VStack(spacing: 2) {
                if bluetooth { BluetoothGlyph().stroke(.white, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)).frame(width: screenWidth * PlayerReferenceStyle.outputSymbolFraction * 0.65, height: screenWidth * PlayerReferenceStyle.outputSymbolFraction) }
                else {
                    Image(systemName: symbol).resizable().scaledToFit()
                        .font(.system(size: screenWidth * PlayerReferenceStyle.outputSymbolFraction, weight: .heavy))
                        .frame(width: screenWidth * PlayerReferenceStyle.outputSymbolFraction,
                               height: screenWidth * PlayerReferenceStyle.outputSymbolFraction)
                }
                Text(bits.map { "\($0)/\(rate)" } ?? rate).font(.custom("AvenirNext-Bold", size: screenWidth * PlayerReferenceStyle.outputTextFraction))
            }
            .foregroundStyle(.white).frame(width: 64, height: 44)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Audio route: \(session.currentRoute.outputs.map(\.portName).joined(separator: ", ")). PCM supplied to session: \(bits.map(String.init) ?? "unknown") bits, \(rate). Hardware bit depth unavailable.")
        }
    }
}

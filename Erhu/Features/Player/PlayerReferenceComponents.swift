import SwiftUI
import UIKit
import AVFoundation

struct PlayerFullBleedBackground<Artwork: View>: View {
    let dominant: Color
    var secondaryDominant: Color? = nil
    var blend = 0.0
    @ViewBuilder var artwork: () -> Artwork

    private func muted(_ color: Color) -> UIColor {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        guard UIColor(color).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return UIColor(red: 0.50, green: 0.31, blue: 0.29, alpha: 1)
        }
        let mutedHue = hue < 0.12 ? hue * 0.5 : hue
        return UIColor(hue: mutedHue, saturation: saturation * 0.55,
                       brightness: min(max(brightness, 0.50), 0.58), alpha: 1)
    }
    var body: some View {
        GeometryReader { geometry in
            let base = Color(uiColor: muted(dominant))
            ZStack(alignment: .top) {
                LinearGradient(colors: [base, base, base.opacity(0.18)],
                               startPoint: .top, endPoint: .bottom)
                    .background(Color(red: 0.10, green: 0.045, blue: 0.035))
                if let secondaryDominant {
                    let next = Color(uiColor: muted(secondaryDominant))
                    LinearGradient(colors: [next, next, next.opacity(0.18)], startPoint: .top, endPoint: .bottom)
                        .background(Color(red: 0.10, green: 0.045, blue: 0.035))
                        .opacity(blend)
                }
                artwork()
                    .frame(width: geometry.size.width, height: geometry.size.height * 0.55)
                    .clipped()
                    .mask {
                        LinearGradient(stops: [.init(color: .white, location: 0),
                                               .init(color: .white, location: 0.75),
                                               .init(color: .clear, location: 1)],
                                       startPoint: .top, endPoint: .bottom)
                    }
                LinearGradient(colors: [.black.opacity(0.40), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: geometry.size.height * 0.12)
            }
        }
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
                if bluetooth { BluetoothGlyph().stroke(.white, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)).frame(width: 11, height: 17) }
                else { Image(systemName: symbol).font(.system(size: 15, weight: .bold)) }
                Text(bits.map { "\($0)/\(rate)" } ?? rate).font(.custom("AvenirNext-Bold", size: 10))
            }
            .foregroundStyle(.white).frame(width: 64, height: 44)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Audio route: \(session.currentRoute.outputs.map(\.portName).joined(separator: ", ")). PCM supplied to session: \(bits.map(String.init) ?? "unknown") bits, \(rate). Hardware bit depth unavailable.")
        }
    }
}

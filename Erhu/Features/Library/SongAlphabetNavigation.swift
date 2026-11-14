import SwiftUI

enum SongAlphabet {
    static let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init) + ["#"]
    static func key(_ title: String) -> String {
        let normalized = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX")).uppercased()
        guard let first = normalized.trimmingCharacters(in: .whitespacesAndNewlines).first,
              ("A"..."Z").contains(String(first)) else { return "#" }
        return String(first)
    }
    static func anchors(_ songs: [Song]) -> [String: Int64] {
        var result: [String: Int64] = [:]
        for song in songs where result[key(song.title)] == nil { result[key(song.title)] = song.id }
        return result
    }
}

struct SongAlphabetNavigation: ViewModifier {
    let songs: [Song]
    let enabled: Bool
    @State private var active: String?
    @Environment(\.palette) private var palette
    private static let width: CGFloat = 24
    private static let height: CGFloat = 14

    func body(content: Content) -> some View {
        let anchors = SongAlphabet.anchors(songs)
        let letters = SongAlphabet.letters.filter { anchors[$0] != nil }
        ScrollViewReader { proxy in
            content.padding(.trailing, enabled && letters.count > 1 ? Self.width : 0)
                .overlay(alignment: .trailing) {
                    if enabled && letters.count > 1 {
                        VStack(spacing: 0) {
                            ForEach(letters, id: \.self) { letter in
                                Text(letter).font(.system(size: 10, weight: .bold))
                                    .frame(width: Self.width, height: Self.height)
                            }
                        }
                        .foregroundStyle(palette.primary)
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                            let index = min(max(Int(value.location.y / Self.height), 0), letters.count - 1)
                            let letter = letters[index]
                            if active != letter, let id = anchors[letter] { active = letter; proxy.scrollTo("amp-song-\(id)", anchor: .top) }
                        }.onEnded { _ in active = nil })
                        .overlay(alignment: .leading) {
                            if let active {
                                Text(active).font(.largeTitle.bold()).padding(Spacing.md)
                                    .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.medium))
                                    .offset(x: -64).allowsHitTesting(false)
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Song alphabet index")
                        .accessibilityValue(active ?? letters.first ?? "")
                        .accessibilityAdjustableAction { direction in
                            let current = letters.firstIndex(of: active ?? "") ?? 0
                            let index = min(max(current + (direction == .increment ? 1 : -1), 0), letters.count - 1)
                            active = letters[index]
                            if let id = anchors[letters[index]] { proxy.scrollTo("amp-song-\(id)", anchor: .top) }
                        }
                    }
                }
        }
    }
}

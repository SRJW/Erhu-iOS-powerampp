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

struct SongAlphabetIndex: View {
    let songs: [Song]
    let scrollTo: (Int64) -> Void
    @State private var active: String?
    @Environment(\.palette) private var palette
    private static let width: CGFloat = 24
    private static let height: CGFloat = 14

    var body: some View {
        let anchors = SongAlphabet.anchors(songs)
        let available = SongAlphabet.letters.filter { anchors[$0] != nil }
        Group {
            if available.count > 1 {
                GeometryReader { geometry in
                    let rowHeight = min(Self.height, geometry.size.height / CGFloat(SongAlphabet.letters.count))
                    VStack(spacing: 0) {
                        ForEach(SongAlphabet.letters, id: \.self) { letter in
                            Text(letter).font(.system(size: 10, weight: .bold))
                                .opacity(anchors[letter] == nil ? 0.25 : 1)
                                .frame(width: Self.width, height: rowHeight)
                        }
                    }
                    .foregroundStyle(palette.primary)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                        let index = min(max(Int(value.location.y / max(rowHeight, 1)), 0), SongAlphabet.letters.count - 1)
                        let forward = SongAlphabet.letters[index...].first { anchors[$0] != nil }
                        let backward = SongAlphabet.letters[...index].last { anchors[$0] != nil }
                        if let letter = forward ?? backward, active != letter, let id = anchors[letter] {
                            active = letter; scrollTo(id)
                        }
                    }.onEnded { _ in active = nil })
                }
                .frame(width: Self.width, height: min(CGFloat(SongAlphabet.letters.count) * Self.height, 360))
                .overlay(alignment: .leading) {
                    if let active {
                        Text(active).font(.largeTitle.bold()).padding(Spacing.md)
                            .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.medium))
                            .offset(x: -64).allowsHitTesting(false)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Song alphabet index")
                .accessibilityValue(active ?? available.first ?? "")
                .accessibilityAdjustableAction { direction in
                    let current = available.firstIndex(of: active ?? "") ?? 0
                    let index = min(max(current + (direction == .increment ? 1 : -1), 0), available.count - 1)
                    active = available[index]
                    if let id = anchors[available[index]] { scrollTo(id) }
                }
            }
        }
    }
}

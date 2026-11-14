import SwiftUI

struct LibrarySectionIcon: View {
    let section: LibrarySection
    var selected = false
    var size: CGFloat = 19
    var weight: Font.Weight = .regular

    var body: some View {
        Image(systemName: selected ? section.selectedIcon : section.icon).font(.system(size: size, weight: weight))
    }
}

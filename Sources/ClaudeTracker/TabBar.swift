import SwiftUI

/// Equal-width segmented tabs. The native segmented picker sizes segments to their labels
/// and insets itself a few points, so it never lines up with the tiles below it.
struct TabBar<Tab: Hashable>: View {
    struct Item: Identifiable {
        let tab: Tab
        let title: String
        var id: Tab { tab }
    }

    private static var height: CGFloat { 26 }
    private static var inset: CGFloat { 2 }

    let items: [Item]
    @Binding var selection: Tab

    var body: some View {
        HStack(spacing: Self.inset) {
            ForEach(items) { item in
                segment(item)
            }
        }
        .padding(Self.inset)
        .frame(height: Self.height)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.07)))
    }

    private func segment(_ item: Item) -> some View {
        let isSelected = item.tab == selection
        return Text(item.title)
            .font(.callout.weight(isSelected ? .semibold : .regular))
            .lineLimit(1)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 5).fill(isSelected ? Color.accentColor : Color.clear))
            .contentShape(Rectangle())
            // A tap gesture rather than a Button: offscreen snapshots render buttons as placeholders.
            .onTapGesture { selection = item.tab }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { selection = item.tab }
    }
}

import SwiftUI

struct AddBlockBar: View {
    let focusedBlockType: BlockType?
    var onConvert: (BlockType) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ConvertButton(
                imageName: "bar.title",
                isActive: focusedBlockType == .title
            ) {
                onConvert(.title)
            }
            .accessibilityIdentifier("convertButton.title")

            ConvertButton(
                imageName: "bar.note",
                isActive: focusedBlockType == .note
            ) {
                onConvert(.note)
            }
            .accessibilityIdentifier("convertButton.note")

            ConvertButton(
                imageName: "bar.todo",
                iconSide: 16,
                isActive: focusedBlockType == .todo
            ) {
                onConvert(.todo)
            }
            .accessibilityIdentifier("convertButton.todo")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .modifier(GlassPillBackground())
        .padding(.bottom, 8)
        .contentShape(Capsule())
    }
}

private struct GlassPillBackground: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: Capsule())
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.primary.opacity(0.06), lineWidth: 0.5))
        }
    }
}

private struct ConvertButton: View {
    let imageName: String
    /// Drawn icon size; todo art reads smaller than title at the same frame, so it uses a larger value.
    var iconSide: CGFloat = 14
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(imageName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: iconSide, height: iconSide)
                .foregroundStyle(isActive ? AnyShapeStyle(Color.primary) : AnyShapeStyle(.tertiary))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
    }
}

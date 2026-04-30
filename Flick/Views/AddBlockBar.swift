import SwiftUI

struct AddBlockBar: View {
    let focusedBlockType: BlockType?
    var onConvert: (BlockType) -> Void

    @Environment(AppSettings.self) private var settings
    @State private var showSettings = false

    var body: some View {
        ZStack {
            HStack(spacing: 4) {
                ConvertButton(
                    monoText: "T",
                    isActive: focusedBlockType == .title,
                    isEnabled: true
                ) {
                    onConvert(.title)
                }
                .accessibilityIdentifier("convertButton.title")

                ConvertButton(
                    systemImage: "text.alignleft",
                    isActive: focusedBlockType == .note,
                    isEnabled: true
                ) {
                    onConvert(.note)
                }
                .accessibilityIdentifier("convertButton.note")

                ConvertButton(
                    systemImage: "checkmark.circle",
                    isActive: focusedBlockType == .todo,
                    isEnabled: true
                ) {
                    onConvert(.todo)
                }
                .accessibilityIdentifier("convertButton.todo")
            }

            HStack {
                Spacer()
                Button {
                    showSettings.toggle()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showSettings, arrowEdge: .bottom) {
                    SettingsPanel()
                        .environment(settings)
                }
            }
        }
        .padding(.bottom, 8)
    }
}

private struct ConvertButton: View {
    var systemImage: String? = nil
    var monoText: String? = nil
    let isActive: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let sys = systemImage {
                    Image(systemName: sys).font(.system(size: 13))
                } else if let t = monoText {
                    Text(t).font(.system(size: 13, weight: .bold, design: .monospaced))
                }
            }
            .foregroundStyle(isActive ? AnyShapeStyle(Color.primary) : AnyShapeStyle(.tertiary))
            .opacity(isEnabled ? 1.0 : 0.35)
            .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

import SwiftUI

extension Notification.Name {
    static let flickBackspacePressed = Notification.Name("flickBackspacePressed")
    static let flickMouseDown = Notification.Name("flickMouseDown")
    static let flickMouseDragged = Notification.Name("flickMouseDragged")
    static let flickMouseUp = Notification.Name("flickMouseUp")
}

struct BlockRow: View {
    @Binding var block: Block
    @FocusState.Binding var focusedID: UUID?
    var isSelected: Bool
    var customPlaceholder: String? = nil
    var onSubmit: () -> Void
    var onInsertAbove: () -> Void
    var onDelete: () -> Void
    var onMoveUp: () -> Void
    var onMoveDown: () -> Void
    var onShiftClick: () -> Void
    var onCommandClick: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if block.type == .todo {
                Button {
                    block.isChecked.toggle()
                } label: {
                    Image(systemName: block.isChecked ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 15))
                        .foregroundStyle(block.isChecked ? Color.primary : .secondary)
                }
                .buttonStyle(.plain)
                .padding(.top, 1)
            }

            TextField("", text: $block.text, axis: block.type == .title ? .horizontal : .vertical)
                .font(textFont)
                .textFieldStyle(.plain)
                .tint(.black)
                .strikethrough(block.isChecked && block.type == .todo, color: .secondary)
                .foregroundStyle(block.isChecked && block.type == .todo ? .tertiary : .primary)
                .lineLimit(block.type == .title ? 1...1 : 1...8)
                .overlay(alignment: .leading) {
                    if block.text.isEmpty && focusedID == block.id, !placeholder.isEmpty {
                        Text(placeholder)
                            .font(textFont)
                            .foregroundStyle(.tertiary)
                            .allowsHitTesting(false)
                    }
                }
                .focused($focusedID, equals: block.id)
                .onKeyPress(keys: [.return], phases: .down) { press in
                    if press.modifiers.contains(.shift) {
                        onInsertAbove()
                    } else {
                        onSubmit()
                    }
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    onMoveUp()
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    onMoveDown()
                    return .handled
                }
                .onReceive(NotificationCenter.default.publisher(for: .flickBackspacePressed)) { _ in
                    guard focusedID == block.id, block.text.isEmpty else { return }
                    if block.type == .note {
                        onDelete()
                    } else {
                        block.type = .note
                        block.isChecked = false
                    }
                }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, block.type == .title ? 0 : 5)
        .frame(height: block.type == .title ? 44 : nil, alignment: .topLeading)
        .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        .simultaneousGesture(
            TapGesture()
                .modifiers(.shift)
                .onEnded { onShiftClick() }
        )
        .simultaneousGesture(
            TapGesture()
                .modifiers(.command)
                .onEnded { onCommandClick() }
        )
        .contextMenu {
            Button("Delete", role: .destructive, action: onDelete)
        }
    }

    private var placeholder: String {
        guard focusedID == block.id else { return "" }
        if let custom = customPlaceholder { return custom }
        switch block.type {
        case .title: return "Title"
        case .note: return "Write something…"
        case .todo: return "To-do"
        }
    }

    private var textFont: Font {
        switch block.type {
        case .title: .custom("NocturneSerifTest-SemiBold", size: 17)
        case .note, .todo: .system(size: 13)
        }
    }
}

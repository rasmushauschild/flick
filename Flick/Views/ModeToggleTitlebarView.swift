import SwiftUI

/// Lives in `NSTitlebarAccessoryViewController` (real title bar), not in the document content.
struct ModeToggleTitlebarView: View {
    @Environment(ModeToggleBridge.self) private var bridge

    var body: some View {
        Button {
            bridge.performToggle()
        } label: {
            Group {
                if bridge.isPermanent {
                    Image(systemName: "calendar")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .frame(width: 28, height: 28)
                } else {
                    Image("mode.permanent")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                        .foregroundStyle(.tertiary)
                        .frame(width: 28, height: 28)
                }
            }
        }
        .buttonStyle(.plain)
        .help(bridge.isPermanent ? "Show daily pages" : "Show notes")
        .frame(width: 28, height: 28)
    }
}

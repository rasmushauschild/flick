import SwiftUI

struct RootView: View {
    /// Fixed width for close placeholder / mode toggle; date strip only lays out *between* these so digits never sit under the icons.
    private let headerChromeSlotWidth: CGFloat = 32

    @Environment(ModeToggleBridge.self) private var modeToggleBridge
    @Environment(WindowDockState.self) private var dock
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var pageMode: PageMode = .daily(Calendar.current.startOfDay(for: Date()))

    private var isPermanent: Bool {
        if case .permanent = pageMode { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 0)
            Group {
                if isPermanent {
                    headerChrome {
                        Text("Notes")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    headerChrome {
                        DateScrubber(selectedDate: $selectedDate)
                    }
                }
            }

            PageView(mode: pageMode)
                .id(pageMode)
        }
        .padding(15)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if #available(macOS 26.0, *) {
                Color.clear
                    .glassEffect(
                        .regular,
                        in: RoundedRectangle(cornerRadius: 30, style: .continuous)
                    )
            } else {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
        }
        .onAppear {
            modeToggleBridge.performToggle = { toggleMode() }
            modeToggleBridge.isPermanent = isPermanent
        }
        .onChange(of: pageMode) { _, _ in
            modeToggleBridge.isPermanent = isPermanent
        }
        .onChange(of: selectedDate) { _, newDate in
            if !isPermanent {
                pageMode = .daily(newDate)
            }
        }
    }

    /// HStack (not ZStack): center fills only the space *between* chrome so the scrubber never draws under the close dot or mode button.
    @ViewBuilder
    private func headerChrome<Center: View>(@ViewBuilder center: () -> Center) -> some View {
        HStack(alignment: .center, spacing: 0) {
            Group {
                if dock.isDocked {
                    Color.clear
                } else {
                    Button {
                        dock.performClose()
                    } label: {
                        Circle()
                            .fill(Color.red.opacity(0.92))
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                    .help("Close window")
                    .contentShape(Circle())
                    .accessibilityIdentifier("flickClose")
                }
            }
            .frame(width: headerChromeSlotWidth, height: 38)
            .offset(y: -3)

            center()
                .frame(maxWidth: .infinity, alignment: .center)

            ModeToggleChromeButton()
                .frame(width: headerChromeSlotWidth, height: 38)
                .offset(y: -3)
        }
        .frame(height: 38)
    }

    private func toggleMode() {
        if isPermanent {
            let today = Calendar.current.startOfDay(for: Date())
            selectedDate = today
            pageMode = .daily(today)
        } else {
            pageMode = .permanent
        }
    }
}

private struct ModeToggleChromeButton: View {
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
                        .frame(width: 32, height: 32)
                } else {
                    Image("mode.permanent")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                        .foregroundStyle(.tertiary)
                        .frame(width: 32, height: 32)
                }
            }
        }
        .buttonStyle(.plain)
        .help(bridge.isPermanent ? "Show daily pages" : "Show notes")
        .frame(width: 32, height: 32)
    }
}

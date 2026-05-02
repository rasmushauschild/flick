import SwiftUI

struct RootView: View {
    /// Fixed width for close placeholder / mode toggle in the header row.
    private let headerChromeSlotWidth: CGFloat = 32

    @Environment(ModeToggleBridge.self) private var modeToggleBridge
    @Environment(WindowDockState.self) private var dock
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    /// Captured when opening permanent notes; restored when returning to daily so the scrubber stays on the prior day.
    @State private var dailyDateBeforePermanent = Calendar.current.startOfDay(for: Date())
    @State private var pageMode: PageMode = .daily(Calendar.current.startOfDay(for: Date()))
    /// Header-wide hover state: drives the scrubber's reveal so the user can scroll/scrub from anywhere in the header.
    @State private var headerHover: Bool = false
    /// Hover state for the floating close dot — shows the traffic-light style "x" glyph when true.
    @State private var isCloseHovered: Bool = false
    /// Incremented when leaving permanent notes so the date strip runs a layout resync (even if `selectedDate` is already today).
    @State private var stripRealignTick: Int = 0

    private var isPermanent: Bool {
        if case .permanent = pageMode { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 0)
            headerChrome {
                ZStack {
                    // Kept alive while viewing permanent notes so `LazyHStack` / scroll position are not torn down.
                    DateScrubber(
                        selectedDate: $selectedDate,
                        isActive: headerHover && !isPermanent,
                        stripRealignTick: stripRealignTick
                    )
                    .opacity(isPermanent ? 0 : 1)
                    .allowsHitTesting(!isPermanent)

                    if isPermanent {
                        Text("Notes")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            PageView(mode: pageMode)
                .id(pageMode)
                .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.18), value: pageMode)
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
                withAnimation(.easeInOut(duration: 0.18)) {
                    pageMode = .daily(newDate)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .flickWindowDidBecomeVisible)) { _ in
            let today = Calendar.current.startOfDay(for: Date())
            selectedDate = today
            if !isPermanent {
                pageMode = .daily(today)
            }
        }
    }

    /// Leading/trailing overlays only (fixed width). A full-width `HStack` + `Spacer` still sat on top of the
    /// scrubber and swallowed clicks on macOS even with `allowsHitTesting(false)` on the spacer.
    @ViewBuilder
    private func headerChrome<Center: View>(@ViewBuilder center: () -> Center) -> some View {
        center()
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .overlay(alignment: .leading) {
                headerLeadingChrome
                    .frame(width: headerChromeSlotWidth, height: 38, alignment: .center)
                    .offset(y: -3)
            }
            .overlay(alignment: .trailing) {
                ModeToggleChromeButton()
                    .frame(width: headerChromeSlotWidth, height: 38, alignment: .center)
                    .offset(y: -3)
            }
            .contentShape(Rectangle())
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    headerHover = hovering
                }
            }
    }

    @ViewBuilder
    private var headerLeadingChrome: some View {
        Group {
            if dock.isDocked {
                Color.clear
            } else {
                Button {
                    dock.performClose()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.red.opacity(0.92))
                            .frame(width: 16, height: 16)
                        if isCloseHovered {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Color.black.opacity(0.55))
                        }
                    }
                }
                .buttonStyle(.plain)
                .onHover { hovering in isCloseHovered = hovering }
                .help("Close window")
                .contentShape(Circle())
                .accessibilityIdentifier("flickClose")
            }
        }
        // Docked: pass clicks/scroll through to the full-width scrubber. Floating: only the close control hits.
        .allowsHitTesting(!dock.isDocked)
    }

    private func toggleMode() {
        if isPermanent {
            let restore = dailyDateBeforePermanent
            selectedDate = restore
            stripRealignTick += 1
            withAnimation(.easeInOut(duration: 0.18)) {
                pageMode = .daily(restore)
            }
        } else {
            dailyDateBeforePermanent = Calendar.current.startOfDay(for: selectedDate)
            withAnimation(.easeInOut(duration: 0.18)) {
                pageMode = .permanent
            }
        }
    }
}

private struct ModeToggleChromeButton: View {
    @Environment(ModeToggleBridge.self) private var bridge

    var body: some View {
        Button {
            bridge.performToggle()
        } label: {
            Image("mode.permanent")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .foregroundStyle(bridge.isPermanent ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .help(bridge.isPermanent ? "Show daily pages" : "Show notes")
        .frame(width: 32, height: 32)
    }
}

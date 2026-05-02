import SwiftUI

struct RootView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(ModeToggleBridge.self) private var modeToggleBridge
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
                    Text("Notes")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(height: 38)
                } else {
                    DateScrubber(selectedDate: $selectedDate)
                }
            }

            PageView(mode: pageMode)
                .id(pageMode)
        }
        .padding(15)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(settings.isTransparent ? AnyShapeStyle(Color.clear) : AnyShapeStyle(Color.white))
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

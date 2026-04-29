import SwiftUI

struct RootView: View {
    @Environment(AppSettings.self) private var settings
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var pageMode: PageMode = .daily(Calendar.current.startOfDay(for: Date()))

    private var isPermanent: Bool {
        if case .permanent = pageMode { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 5)
            ZStack {
                if isPermanent {
                    Text("Notes")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(height: 38)
                } else {
                    DateScrubber(selectedDate: $selectedDate)
                }

                HStack {
                    Spacer()
                    Button {
                        toggleMode()
                    } label: {
                        Image(systemName: isPermanent ? "calendar" : "note.text")
                            .font(.system(size: 12))
                            .foregroundStyle(.quaternary)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 6)
                }
            }

            PageView(mode: pageMode)
                .id(pageMode)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(settings.isTransparent ? AnyShapeStyle(Color.clear) : AnyShapeStyle(Color.white))
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

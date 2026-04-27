import SwiftUI

struct RootView: View {
    @Environment(AppSettings.self) private var settings
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 5)
            DateScrubber(selectedDate: $selectedDate)
            PageView(selectedDate: selectedDate)
                .id(Calendar.current.startOfDay(for: selectedDate))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(settings.isTransparent ? AnyShapeStyle(Color.clear) : AnyShapeStyle(Color.white))
    }
}

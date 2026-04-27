import SwiftUI

struct SettingsPanel: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        VStack(alignment: .leading, spacing: 14) {
            Toggle("Transparent background", isOn: $settings.isTransparent)
            Toggle("Launch at startup", isOn: $settings.launchAtStartup)
        }
        .font(.system(size: 13))
        .padding(16)
        .frame(width: 220)
    }
}

import Foundation
import ServiceManagement
import Observation

@Observable
class AppSettings {
    var isTransparent: Bool = UserDefaults.standard.bool(forKey: "isTransparent") {
        didSet { UserDefaults.standard.set(isTransparent, forKey: "isTransparent") }
    }

    var launchAtStartup: Bool = SMAppService.mainApp.status == .enabled {
        didSet {
            if launchAtStartup {
                try? SMAppService.mainApp.register()
            } else {
                try? SMAppService.mainApp.unregister()
            }
        }
    }
}

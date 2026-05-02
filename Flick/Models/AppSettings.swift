import Foundation
import ServiceManagement
import Observation

@Observable
class AppSettings {
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

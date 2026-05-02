import Foundation
import Observation

/// Shared state so the title-bar accessory button stays in sync with `RootView`’s `pageMode`.
@Observable
final class ModeToggleBridge {
    var isPermanent = false
    var performToggle: () -> Void = {}
}

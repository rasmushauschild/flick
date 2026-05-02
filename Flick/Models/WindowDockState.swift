import Foundation
import Observation

/// Syncs menu-bar dock vs floating window so SwiftUI can show/hide the in-content close control.
@Observable
final class WindowDockState {
    var isDocked: Bool = true
    var performClose: () -> Void = {}
}

import AppKit
import SwiftUI

/// Borderless windows are not key by default; without key status the editor stays disabled for UI tests and typing.
final class FlickWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class FlickFieldEditor: NSTextView {
    var suppressSelectAll = false

    override func selectAll(_ sender: Any?) {
        if suppressSelectAll {
            let len = (self.string as NSString).length
            self.setSelectedRange(NSRange(location: len, length: 0))
        } else {
            super.selectAll(sender)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private var window: FlickWindow!
    private var hostingController: NSHostingController<AnyView>!
    private let fieldEditor: FlickFieldEditor = {
        let editor = FlickFieldEditor()
        editor.isFieldEditor = true
        return editor
    }()

    private var isDocked = true
    private var isProgrammaticMove = false
    private var clickOutsideMonitor: Any?
    private var keyMonitor: Any?

    let store = Store()
    let settings = AppSettings()
    let modeToggleBridge = ModeToggleBridge()
    let windowDockState = WindowDockState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupWindow()
        setupKeyMonitor()


        // UI test bootstrap: auto-show the window so the test runner doesn't have to
        // click the menu bar icon (which is awkward to automate).
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isDocked = false
                self.windowDockState.isDocked = false
                self.window.level = .normal
                NSApp.activate(ignoringOtherApps: true)
                self.window.center()
                self.window.makeKeyAndOrderFront(nil)
            }
        }
    }

    private func setupKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 51 {
                NotificationCenter.default.post(name: .flickBackspacePressed, object: nil)
            }
            return event
        }

    }

    // MARK: - Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.isVisible = true
        statusItem.behavior = []
        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "Flick") {
                button.image = image
            } else {
                button.title = "Flick"
            }
            button.action = #selector(statusItemClicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showStatusMenu(from: sender)
        } else {
            toggleWindow()
        }
    }

    private func showStatusMenu(from button: NSStatusBarButton) {
        let menu = NSMenu()

        let launch = NSMenuItem(
            title: "Launch at startup",
            action: #selector(toggleLaunchAtStartup),
            keyEquivalent: ""
        )
        launch.target = self
        launch.state = settings.launchAtStartup ? .on : .off
        menu.addItem(launch)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit Flick",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quit)

        // Standard "transient menu" pattern: assign the menu, click the button to
        // pop it up, then clear it so left-click still routes to our action.
        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func toggleLaunchAtStartup() {
        settings.launchAtStartup.toggle()
    }

    @objc private func toggleWindow() {
        if window.isVisible {
            hideWindow()
        } else {
            if isDocked {
                positionWindow()
            }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            applyDockedState()
        }
    }

    private func hideWindow() {
        stopOutsideMonitor()
        isDocked = true
        windowDockState.isDocked = true
        window.orderOut(nil)
    }

    private func positionWindow() {
        guard let button = statusItem.button,
              let buttonWindow = button.window else { return }
        isProgrammaticMove = true
        defer { isProgrammaticMove = false }

        let buttonRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let wf = window.frame
        var x = buttonRect.midX - wf.width / 2
        let y = buttonRect.minY - wf.height - 8

        if let screen = NSScreen.main {
            let vf = screen.visibleFrame
            x = max(vf.minX + 8, min(x, vf.maxX - wf.width - 8))
        }
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - Window setup

    private func setupWindow() {
        // Borderless so there is no separate title-bar / unified-toolbar drag strip
        // above the clipped SwiftUI content (that strip stayed draggable and looked empty).
        window = FlickWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 453),
            styleMask: [.borderless, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        // Drag only from the hosting view / SwiftUI "background", not system chrome.
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 240, height: 360)
        window.delegate = self
        window.hasShadow = true

        // The visible chrome is now drawn entirely by SwiftUI (Liquid Glass
        // background + rounded clip), so the window itself must be transparent
        // so its shadow/backdrop follow our rounded shape.
        window.isOpaque = false
        window.backgroundColor = .clear

        hostingController = NSHostingController(
            rootView: AnyView(
                RootView()
                    .environment(store)
                    .environment(modeToggleBridge)
                    .environment(windowDockState)
            )
        )
        hostingController.view.frame = NSRect(x: 0, y: 0, width: 280, height: 453)
        hostingController.view.autoresizingMask = [.width, .height]

        window.contentView = hostingController.view

        // Backstop: if Tahoe's automatic radius is still smaller than the
        // SwiftUI glass shape, mask the contentView at 30pt so the visible
        // window matches the SwiftUI background exactly.
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.cornerRadius = 30
        hostingController.view.layer?.cornerCurve = .continuous
        hostingController.view.layer?.masksToBounds = true

        windowDockState.performClose = { [weak self] in
            self?.window?.performClose(nil)
        }
    }

    // MARK: - Docked state

    private func applyDockedState() {
        windowDockState.isDocked = isDocked
        // In-content SwiftUI close dot replaces the traffic-light when floating.
        window.standardWindowButton(.closeButton)?.isHidden = true
        if isDocked {
            window.level = .normal
            startOutsideMonitor()
        } else {
            window.level = .floating
            stopOutsideMonitor()
        }
    }

    private func startOutsideMonitor() {
        guard clickOutsideMonitor == nil else { return }
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, self.window.isVisible, self.isDocked else { return }
            let loc = NSEvent.mouseLocation
            if let btn = self.statusItem.button, let bw = btn.window {
                let br = bw.convertToScreen(btn.convert(btn.bounds, to: nil))
                if br.contains(loc) { return }
            }
            if !self.window.frame.contains(loc) {
                self.hideWindow()
            }
        }
    }

    private func stopOutsideMonitor() {
        if let m = clickOutsideMonitor { NSEvent.removeMonitor(m); clickOutsideMonitor = nil }
    }

    // MARK: - NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        guard !isProgrammaticMove, isDocked else { return }
        isDocked = false
        applyDockedState()
    }

    func windowWillReturnFieldEditor(_ sender: NSWindow, to client: Any?) -> Any? {
        fieldEditor.suppressSelectAll = true
        DispatchQueue.main.async { [weak self] in
            self?.fieldEditor.suppressSelectAll = false
        }
        return fieldEditor
    }

    func windowWillClose(_ notification: Notification) {
        isDocked = true
        windowDockState.isDocked = true
        stopOutsideMonitor()
    }
}

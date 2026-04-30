import AppKit
import SwiftUI

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
    private var window: NSWindow!
    private var hostingController: NSHostingController<AnyView>!
    private var visualEffectView: NSVisualEffectView!
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupWindow()
        setupKeyMonitor()
        observeSettings()


        // UI test bootstrap: auto-show the window so the test runner doesn't have to
        // click the menu bar icon (which is awkward to automate).
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isDocked = false
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
            button.action = #selector(toggleWindow)
            button.target = self
        }
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
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 453),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.minSize = NSSize(width: 240, height: 360)
        window.delegate = self

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 453))
        container.autoresizingMask = [.width, .height]

        visualEffectView = NSVisualEffectView(frame: container.bounds)
        visualEffectView.material = .menu
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.autoresizingMask = [.width, .height]
        container.addSubview(visualEffectView)

        hostingController = NSHostingController(
            rootView: AnyView(
                RootView()
                    .environment(store)
                    .environment(settings)
            )
        )
        hostingController.view.frame = container.bounds
        hostingController.view.autoresizingMask = [.width, .height]
        container.addSubview(hostingController.view)

        window.contentView = container
        updateAppearance()
    }

    // MARK: - Docked state

    private func applyDockedState() {
        let closeButton = window.standardWindowButton(.closeButton)
        closeButton?.isHidden = isDocked
        if !isDocked {
            DispatchQueue.main.async { [weak self] in
                self?.positionCloseButton()
            }
        }
        if isDocked {
            window.level = .normal
            startOutsideMonitor()
        } else {
            window.level = .floating
            stopOutsideMonitor()
        }
    }

    private var closeButtonObserver: NSKeyValueObservation?
    private var isReapplyingCloseButtonFrame = false

    private func positionCloseButton() {
        guard let close = window.standardWindowButton(.closeButton),
              let titleBar = close.superview else { return }
        let titleBarHeight = titleBar.bounds.height
        let buttonHeight = close.frame.height
        let target = NSPoint(x: 13, y: max(0, titleBarHeight - 13 - buttonHeight))
        guard close.frame.origin != target else { return }
        isReapplyingCloseButtonFrame = true
        var frame = close.frame
        frame.origin = target
        close.frame = frame
        isReapplyingCloseButtonFrame = false

        if closeButtonObserver == nil {
            closeButtonObserver = close.observe(\.frame, options: [.new, .old]) { [weak self] button, change in
                guard let self,
                      !self.isReapplyingCloseButtonFrame,
                      change.newValue?.origin != change.oldValue?.origin else { return }
                let goal = NSPoint(x: 13, y: max(0, (button.superview?.bounds.height ?? 0) - 13 - button.frame.height))
                if button.frame.origin != goal {
                    DispatchQueue.main.async { self.positionCloseButton() }
                }
            }
        }
    }

    func windowDidResize(_ notification: Notification) {
        if !isDocked { positionCloseButton() }
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
        stopOutsideMonitor()
    }

    // MARK: - Appearance

    private func updateAppearance() {
        hostingController.view.wantsLayer = true

        if settings.isTransparent {
            window.appearance = nil
            window.backgroundColor = .clear
            window.isOpaque = false
            visualEffectView.isHidden = false
            hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
        } else {
            window.appearance = NSAppearance(named: .aqua)
            window.backgroundColor = .white
            window.isOpaque = true
            visualEffectView.isHidden = true
            hostingController.view.layer?.backgroundColor = NSColor.white.cgColor
        }
    }

    private func observeSettings() {
        withObservationTracking {
            _ = settings.isTransparent
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.updateAppearance()
                self?.observeSettings()
            }
        }
    }
}

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
        statusItem.button?.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "Flick")
        statusItem.button?.action = #selector(toggleWindow)
        statusItem.button?.target = self
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
        visualEffectView.material = .popover
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
        window.standardWindowButton(.closeButton)?.isHidden = isDocked
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

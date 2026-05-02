import SwiftUI
import AppKit

struct PageView: View {
    @Environment(Store.self) private var store
    let mode: PageMode

    @State private var blocks: [Block] = []
    @State private var pageID: String = ""
    @State private var focusedBlockType: BlockType? = nil
    /// Window-base rect of the floating `AddBlockBar`, updated from an AppKit sizing view (SwiftUI owns hit testing over the editor).
    @State private var toolStripCursor = ToolStripCursorState()

    var body: some View {
        ZStack(alignment: .bottom) {
            FlickTextEditor(
                blocks: $blocks,
                focusedBlockType: $focusedBlockType
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            AddBlockBar(
                focusedBlockType: focusedBlockType,
                onConvert: { newType in
                    NotificationCenter.default.post(
                        name: .flickConvertParagraph,
                        object: newType.rawValue
                    )
                }
            )
            .background(
                ToolStripFrameReporter { toolStripCursor.stripRectInWindow = $0 }
            )
        }
        .onAppear {
            reload()
            toolStripCursor.installMouseMonitor()
        }
        .onDisappear {
            toolStripCursor.removeMouseMonitor()
        }
        .onChange(of: blocks) { save() }
    }

    private func reload() {
        let page = store.page(for: mode)
        pageID = page.id
        var loaded = page.blocks.isEmpty ? [Block(type: .note, text: "")] : page.blocks
        // Always keep an empty .note "buffer" line at the bottom so that the last
        // paragraph in the editor is never a todo/title (avoids the empty-trailing-todo
        // checkbox-drawing edge case).
        if loaded.last?.type != .note || loaded.last?.text.isEmpty == false {
            loaded.append(Block(type: .note, text: ""))
        }
        blocks = loaded
    }

    private func save() {
        var toSave = blocks
        // Strip the trailing buffer line(s) before persisting.
        while let last = toSave.last, last.type == .note, last.text.isEmpty, toSave.count > 1 {
            toSave.removeLast()
        }
        // If every remaining block is empty or whitespace-only, treat the page as
        // having no real content and remove it from the store entirely.
        let hasRealContent = toSave.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard hasRealContent else {
            store.removePage(id: pageID)
            return
        }
        store.update(DayPage(id: pageID, blocks: toSave))
    }
}

// MARK: - Cursor over AddBlockBar (SwiftUI sits above NSTextView; local monitor + deferred set beats I-beam)

private final class ToolStripCursorState {
    var stripRectInWindow: CGRect = .zero
    private var mouseMonitor: Any?

    func installMouseMonitor() {
        removeMouseMonitor()
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            guard let self else { return event }
            var r = self.stripRectInWindow
            guard r.width > 2, r.height > 2 else { return event }
            r = r.insetBy(dx: -6, dy: -6)
            if r.contains(event.locationInWindow) {
                // Local monitors run before event delivery; NSTextView would still set I-beam afterward without async.
                DispatchQueue.main.async {
                    NSCursor.arrow.set()
                }
            }
            return event
        }
    }

    func removeMouseMonitor() {
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }
    }

    deinit {
        removeMouseMonitor()
    }
}

private struct ToolStripFrameReporter: NSViewRepresentable {
    var onWindowFrameChange: (CGRect) -> Void

    func makeNSView(context: Context) -> NSView {
        let v = ToolStripFrameReportView()
        v.onWindowFrameChange = onWindowFrameChange
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? ToolStripFrameReportView)?.onWindowFrameChange = onWindowFrameChange
    }
}

private final class ToolStripFrameReportView: NSView {
    var onWindowFrameChange: ((CGRect) -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override var isOpaque: Bool { false }

    override func layout() {
        super.layout()
        guard window != nil else { return }
        onWindowFrameChange?(convert(bounds, to: nil))
    }
}

import AppKit
import SwiftUI

/// SwiftUI wrapper around an NSTextView that edits a single attributed string built from [Block].
/// All native macOS text behaviors (drag-select, cut/copy/paste, find, autocorrect off, etc.) are inherited.
struct FlickTextEditor: NSViewRepresentable {
    @Binding var blocks: [Block]
    @Binding var focusedBlockType: BlockType?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let textView = FlickTextView(frame: .zero)
        textView.setAccessibilityIdentifier("flickEditor")
        textView.translatesAutoresizingMaskIntoConstraints = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = .width

        textView.isEditable = true
        textView.isRichText = true
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.usesFontPanel = false
        textView.usesRuler = false
        textView.usesInspectorBar = false

        textView.textContainerInset = NSSize(width: 14, height: 8)
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.insertionPointColor = .black

        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.lineFragmentPadding = 0

        textView.delegate = context.coordinator
        context.coordinator.textView = textView

        scrollView.documentView = textView

        // Initial population
        context.coordinator.replaceContents(with: blocks, in: textView)

        // Listen for paragraph-conversion commands from AddBlockBar.
        context.coordinator.installConversionObserver()

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? FlickTextView else { return }
        context.coordinator.parent = self
        let currentBlocks = BlockParser.blocks(from: textView.attributedString())
        if !FlickTextEditor.blocksHaveSameContent(currentBlocks, blocks) {
            context.coordinator.replaceContents(with: blocks, in: textView)
        }
    }

    /// Compare blocks ignoring their UUIDs — UUIDs are regenerated on every parse,
    /// so identity-based equality would always report a change.
    static func blocksHaveSameContent(_ a: [Block], _ b: [Block]) -> Bool {
        guard a.count == b.count else { return false }
        for (x, y) in zip(a, b) {
            if x.type != y.type || x.text != y.text || x.isChecked != y.isChecked {
                return false
            }
        }
        return true
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        weak var textView: FlickTextView?
        var parent: FlickTextEditor
        private var isApplyingProgrammaticChange = false
        private var conversionObserver: Any?

        init(_ parent: FlickTextEditor) {
            self.parent = parent
        }

        deinit {
            if let conversionObserver {
                NotificationCenter.default.removeObserver(conversionObserver)
            }
        }

        func installConversionObserver() {
            conversionObserver = NotificationCenter.default.addObserver(
                forName: .flickConvertParagraph,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let raw = notification.object as? String,
                      let type = BlockType(rawValue: raw),
                      let textView = self?.textView else { return }
                textView.convertCurrentParagraph(to: type)
                self?.syncBlocksFromStorage()
                self?.updateFocusedBlockType()
            }
        }

        /// Replace the text view's content with the attributed string for these blocks.
        func replaceContents(with blocks: [Block], in textView: FlickTextView) {
            isApplyingProgrammaticChange = true
            defer { isApplyingProgrammaticChange = false }
            let attr = blocks.toAttributedString()
            textView.textStorage?.setAttributedString(attr)
            ensureTrailingBuffer(in: textView)
            updateFocusedBlockType()
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingProgrammaticChange,
                  let textView = self.textView else { return }
            ensureParagraphAttributes(in: textView)
            ensureTrailingBuffer(in: textView)
            syncBlocksFromStorage()
            updateFocusedBlockType()
        }

        /// Make sure the storage always ends with an empty .note paragraph. This is the
        /// "buffer line" the user sees at the bottom; it guarantees that the last
        /// paragraph in the editor is never a todo/title, which sidesteps the
        /// empty-trailing-todo layout bug.
        private func ensureTrailingBuffer(in textView: FlickTextView) {
            guard let storage = textView.textStorage else { return }
            let nsString = storage.string as NSString
            let length = nsString.length

            var needsBuffer = true
            if length > 0 {
                let lastParaRange = nsString.paragraphRange(for: NSRange(location: length - 1, length: 0))
                let probe = max(0, min(lastParaRange.location, length - 1))
                let attrs = storage.attributes(at: probe, effectiveRange: nil)
                let raw = attrs[.flickBlockType] as? String ?? ""
                let type = BlockType(rawValue: raw) ?? .note

                var textLength = lastParaRange.length
                if textLength > 0 {
                    let lastIdx = NSMaxRange(lastParaRange) - 1
                    let lastChar = nsString.substring(with: NSRange(location: lastIdx, length: 1))
                    if lastChar == "\n" || lastChar == "\r" {
                        textLength -= 1
                    }
                }
                if textLength == 0 && type == .note {
                    needsBuffer = false
                }
            }

            guard needsBuffer else { return }

            let savedSelection = textView.selectedRange()
            let savedTypingAttributes = textView.typingAttributes

            let bufferAttrs = BlockAttributes.attributes(for: Block(type: .note, text: ""))
            let buffer = NSAttributedString(string: "\n", attributes: bufferAttrs)
            let savedFlag = isApplyingProgrammaticChange
            isApplyingProgrammaticChange = true
            storage.append(buffer)
            isApplyingProgrammaticChange = savedFlag

            // Restore cursor / typing attributes — appending at the end can otherwise
            // nudge the insertion point onto the freshly-added empty paragraph.
            textView.setSelectedRange(savedSelection)
            textView.typingAttributes = savedTypingAttributes
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            updateFocusedBlockType()
        }

        private func syncBlocksFromStorage() {
            guard let textView else { return }
            let newBlocks = BlockParser.blocks(from: textView.attributedString())
            if !FlickTextEditor.blocksHaveSameContent(newBlocks, parent.blocks) {
                DispatchQueue.main.async { [weak self] in
                    self?.parent.blocks = newBlocks
                }
            }
        }

        private func updateFocusedBlockType() {
            guard let textView else { return }
            let type = textView.currentParagraphBlockType()
            if parent.focusedBlockType != type {
                DispatchQueue.main.async { [weak self] in
                    self?.parent.focusedBlockType = type
                }
            }
        }

        /// Make sure every paragraph has full flick attributes. After typing or pasting, new
        /// runs may not inherit our paragraph-level attributes; we reapply here.
        private func ensureParagraphAttributes(in textView: FlickTextView) {
            guard let storage = textView.textStorage else { return }
            let nsString = storage.string as NSString
            guard nsString.length > 0 else { return }

            storage.beginEditing()
            defer { storage.endEditing() }

            var lastType: BlockType = .note
            var lastChecked = false

            var paragraphRanges: [NSRange] = []
            nsString.enumerateSubstrings(
                in: NSRange(location: 0, length: nsString.length),
                options: [.byParagraphs, .substringNotRequired]
            ) { _, range, _, _ in
                paragraphRanges.append(range)
            }

            for range in paragraphRanges {
                let probe = max(0, min(range.location, storage.length - 1))
                let attrs = storage.attributes(at: probe, effectiveRange: nil)

                let type: BlockType
                if let raw = attrs[.flickBlockType] as? String, let t = BlockType(rawValue: raw) {
                    type = t
                } else {
                    type = lastType
                }
                let checked = (attrs[.flickIsChecked] as? Bool) ?? lastChecked

                let block = Block(type: type, text: "", isChecked: type == .todo ? checked : false)
                let baseAttrs = BlockAttributes.attributes(for: block)

                var fullRange = range
                if NSMaxRange(fullRange) < storage.length {
                    if nsString.substring(with: NSRange(location: NSMaxRange(fullRange), length: 1)) == "\n" {
                        fullRange.length += 1
                    }
                }
                if fullRange.length > 0 {
                    storage.setAttributes(baseAttrs, range: fullRange)
                }

                lastType = type
                lastChecked = type == .todo ? checked : false
            }

            // Keep the typing attributes in sync with the cursor's paragraph so that
            // typed characters inherit the correct block type.
            let sel = textView.selectedRange()
            if storage.length > 0 {
                let probe = max(0, min(sel.location, storage.length - 1))
                let attrs = storage.attributes(at: probe, effectiveRange: nil)
                textView.typingAttributes = attrs
            }
        }
    }
}

// MARK: - NSTextView subclass

final class FlickTextView: NSTextView {
    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            // Don't auto-select-all on focus.
            let len = (string as NSString).length
            let current = selectedRange()
            if current.length == len && len > 0 {
                setSelectedRange(NSRange(location: len, length: 0))
            }
        }
        return result
    }

    // MARK: Drawing checkboxes in the leading gutter

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawCheckboxes(in: dirtyRect)
    }

    private func drawCheckboxes(in dirtyRect: NSRect) {
        for entry in todoCheckboxEntries() {
            if entry.rect.intersects(dirtyRect) {
                drawCheckbox(in: entry.rect, checked: entry.checked)
            }
        }
    }

    /// Walks line fragments and produces one checkbox entry per todo paragraph at the
    /// y-position of the paragraph's first line.
    private func todoCheckboxEntries() -> [(rect: NSRect, checked: Bool)] {
        guard let storage = textStorage,
              let layoutManager = layoutManager,
              let textContainer = textContainer else { return [] }
        let nsString = storage.string as NSString
        let length = nsString.length
        guard length > 0 else { return [] }

        // Force glyph generation and layout for all characters so the line fragment
        // exists for a freshly inserted empty trailing paragraph.
        let fullRange = NSRange(location: 0, length: length)
        layoutManager.ensureGlyphs(forCharacterRange: fullRange)
        layoutManager.ensureLayout(forCharacterRange: fullRange)
        layoutManager.ensureLayout(for: textContainer)

        let allGlyphs = NSRange(location: 0, length: layoutManager.numberOfGlyphs)
        var drawn = Set<Int>()
        var maxLineBottom: CGFloat = 0
        var entries: [(rect: NSRect, checked: Bool)] = []

        func consider(lineRect: NSRect, paragraphStart: Int) {
            if drawn.contains(paragraphStart) { return }
            drawn.insert(paragraphStart)

            let probe = max(0, min(paragraphStart, length - 1))
            let attrs = storage.attributes(at: probe, effectiveRange: nil)
            guard let raw = attrs[.flickBlockType] as? String,
                  raw == BlockType.todo.rawValue else { return }
            let checked = (attrs[.flickIsChecked] as? Bool) ?? false

            let size: CGFloat = 14
            let x = textContainerInset.width
            let y = lineRect.minY + textContainerInset.height + (lineRect.height - size) / 2
            entries.append((NSRect(x: x, y: y, width: size, height: size), checked))
        }

        if allGlyphs.length > 0 {
            layoutManager.enumerateLineFragments(forGlyphRange: allGlyphs) { lineRect, _, _, lineGlyphRange, _ in
                maxLineBottom = max(maxLineBottom, lineRect.maxY)
                let lineCharRange = layoutManager.characterRange(forGlyphRange: lineGlyphRange, actualGlyphRange: nil)
                let paraRange = nsString.paragraphRange(for: NSRange(location: lineCharRange.location, length: 0))
                consider(lineRect: lineRect, paragraphStart: paraRange.location)
            }
        }

        // Final fallback for the LAST paragraph (where the bug surfaces): if it's a
        // todo and its line wasn't enumerated above, place the checkbox using the
        // extra line fragment, or below the last laid-out line if even extra is empty.
        let lastParaRange = nsString.paragraphRange(for: NSRange(location: length - 1, length: 0))
        if !drawn.contains(lastParaRange.location) {
            let probe = max(0, min(lastParaRange.location, length - 1))
            let attrs = storage.attributes(at: probe, effectiveRange: nil)
            if let raw = attrs[.flickBlockType] as? String, raw == BlockType.todo.rawValue {
                let extra = layoutManager.extraLineFragmentRect
                if extra.height > 0 {
                    consider(lineRect: extra, paragraphStart: lastParaRange.location)
                } else {
                    let font = (attrs[.font] as? NSFont) ?? NSFont.systemFont(ofSize: 13)
                    let estimatedHeight = font.boundingRectForFont.height + 2
                    let computed = NSRect(
                        x: 0,
                        y: maxLineBottom,
                        width: textContainer.size.width,
                        height: estimatedHeight
                    )
                    consider(lineRect: computed, paragraphStart: lastParaRange.location)
                }
            }
        }

        return entries
    }

    /// Returns the line-fragment rect for a paragraph. Uses `lineFragmentRect(forGlyphAt:)`
    /// which works for both content paragraphs and empty paragraphs (whose only character
    /// is a non-rendering line break).
    private func paragraphLineRect(
        for paraRange: NSRange,
        length: Int,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer
    ) -> NSRect? {
        // Pick a character that lives on this paragraph's line: the first content char if any,
        // otherwise the paragraph's trailing terminator.
        let charIndex: Int
        if paraRange.length > 0 {
            charIndex = paraRange.location
        } else if NSMaxRange(paraRange) < length {
            charIndex = NSMaxRange(paraRange)
        } else {
            // No characters at all → fall back to the extra line fragment.
            let extra = layoutManager.extraLineFragmentRect
            return extra.height > 0 ? extra : nil
        }

        let glyphIndex = layoutManager.glyphIndexForCharacter(at: charIndex)
        let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        if lineRect.height > 0 {
            return lineRect
        }
        let extra = layoutManager.extraLineFragmentRect
        return extra.height > 0 ? extra : nil
    }

    private func drawCheckbox(in rect: NSRect, checked: Bool) {
        let path = NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
        path.lineWidth = 1.2
        if checked {
            NSColor.labelColor.setStroke()
            NSColor.labelColor.withAlphaComponent(0.85).setFill()
            path.fill()
            path.stroke()

            // Checkmark (NSTextView is flipped: minY = top, maxY = bottom)
            let check = NSBezierPath()
            let inset = rect.insetBy(dx: 3, dy: 3.5)
            check.move(to: NSPoint(x: inset.minX, y: inset.midY))
            check.line(to: NSPoint(x: inset.midX - 0.5, y: inset.maxY))
            check.line(to: NSPoint(x: inset.maxX, y: inset.minY + 1))
            check.lineWidth = 1.4
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            NSColor.windowBackgroundColor.setStroke()
            check.stroke()
        } else {
            NSColor.tertiaryLabelColor.setStroke()
            path.stroke()
        }
    }

    // MARK: Click → toggle checkbox

    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        if didHandleCheckboxClick(at: pt) { return }
        super.mouseDown(with: event)
    }

    private func didHandleCheckboxClick(at point: NSPoint) -> Bool {
        guard let storage = textStorage,
              let layoutManager = layoutManager,
              let textContainer = textContainer else { return false }

        // Only consider clicks in the leading gutter zone (before todo text indent).
        let gutterMaxX = textContainerInset.width + BlockAttributes.todoIndent
        guard point.x < gutterMaxX else { return false }

        // Find the character at the click's Y coordinate (probe at the indented x where text actually lives).
        let containerPoint = NSPoint(
            x: BlockAttributes.todoIndent + 1,
            y: point.y - textContainerInset.height
        )
        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
        let length = (storage.string as NSString).length
        guard length > 0 else { return false }

        let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        let nsString = storage.string as NSString
        let paraRange = nsString.paragraphRange(for: NSRange(location: min(charIndex, length - 1), length: 0))
        let probe = max(0, min(paraRange.location, length - 1))
        let attrs = storage.attributes(at: probe, effectiveRange: nil)
        guard let raw = attrs[.flickBlockType] as? String,
              raw == BlockType.todo.rawValue else { return false }

        toggleTodoChecked(paragraphRange: paraRange)
        return true
    }

    private func toggleTodoChecked(paragraphRange: NSRange) {
        guard let storage = textStorage else { return }
        let probe = max(0, min(paragraphRange.location, storage.length - 1))
        guard probe < storage.length else { return }
        let currentChecked = (storage.attribute(.flickIsChecked, at: probe, effectiveRange: nil) as? Bool) ?? false
        let newChecked = !currentChecked

        // NSString.paragraphRange(for:) already includes the trailing terminator —
        // do NOT expand further or we'll set attributes on the next paragraph too.
        let block = Block(type: .todo, text: "", isChecked: newChecked)
        let attrs = BlockAttributes.attributes(for: block)
        storage.beginEditing()
        if paragraphRange.length > 0 {
            storage.setAttributes(attrs, range: paragraphRange)
        }
        storage.endEditing()

        // Notify our delegate so the SwiftUI binding gets the new state.
        delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: self))
        needsDisplay = true
    }

    // MARK: Block conversion (called by AddBlockBar via notification)

    func convertCurrentParagraph(to newType: BlockType) {
        guard let storage = textStorage else { return }
        let nsString = storage.string as NSString
        let sel = selectedRange()
        // paragraphRange(for:) already includes the trailing terminator. Don't
        // expand it — doing so would spill attributes onto the next paragraph.
        let paraRange = nsString.paragraphRange(for: NSRange(location: min(sel.location, nsString.length), length: 0))

        let block = Block(type: newType, text: "", isChecked: false)
        let attrs = BlockAttributes.attributes(for: block)
        storage.beginEditing()
        if paraRange.length > 0 {
            storage.setAttributes(attrs, range: paraRange)
        }
        typingAttributes = attrs
        storage.endEditing()
        needsDisplay = true
    }

    func currentParagraphBlockType() -> BlockType? {
        guard let storage = textStorage, storage.length > 0 else { return nil }
        let sel = selectedRange()
        let probe = max(0, min(sel.location, storage.length - 1))
        let attrs = storage.attributes(at: probe, effectiveRange: nil)
        guard let raw = attrs[.flickBlockType] as? String else { return nil }
        return BlockType(rawValue: raw)
    }

    // MARK: Key handling — backspace conversion + shift+enter insert above

    override func keyDown(with event: NSEvent) {
        // Backspace on empty title/todo → demote to note
        if event.keyCode == 51 {
            if demoteEmptyTitleOrTodoToNote() { return }
        }
        // Shift+Return → insert paragraph above
        if event.keyCode == 36 && event.modifierFlags.contains(.shift) {
            insertParagraphAbove()
            return
        }
        super.keyDown(with: event)
    }

    override func insertNewline(_ sender: Any?) {
        if demoteEmptyTitleOrTodoToNote() { return }
        super.insertNewline(sender)
    }

    /// If the cursor is on an empty title or todo paragraph, change its type to .note (no
    /// merge, no new paragraph). Returns true if the conversion happened.
    private func demoteEmptyTitleOrTodoToNote() -> Bool {
        guard let storage = textStorage else { return false }
        let sel = selectedRange()
        guard sel.length == 0 else { return false }

        let nsString = storage.string as NSString
        guard let (subRange, enclosingRange) = paragraphRanges(at: sel.location, in: nsString) else {
            return false
        }

        // The paragraph is "empty" if it has no characters before its terminator.
        guard subRange.length == 0 else { return false }

        // Read the type from the paragraph's first character (the terminator if it's empty).
        let probe = max(0, min(enclosingRange.location, storage.length - 1))
        guard probe < storage.length else { return false }
        let attrs = storage.attributes(at: probe, effectiveRange: nil)
        guard let raw = attrs[.flickBlockType] as? String,
              let type = BlockType(rawValue: raw) else { return false }
        guard type == .title || type == .todo else { return false }

        // Convert to .note.
        let block = Block(type: .note, text: "", isChecked: false)
        let newAttrs = BlockAttributes.attributes(for: block)

        storage.beginEditing()
        if enclosingRange.length > 0 {
            storage.setAttributes(newAttrs, range: enclosingRange)
        }
        typingAttributes = newAttrs
        storage.endEditing()

        delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: self))
        needsDisplay = true
        rebuildCheckboxTrackingAreas()
        return true
    }

    /// Find the paragraph's substring range (no terminator) and enclosing range (with terminator)
    /// that contain the given character location.
    private func paragraphRanges(at location: Int, in nsString: NSString) -> (sub: NSRange, enclosing: NSRange)? {
        var found: (NSRange, NSRange)? = nil
        nsString.enumerateSubstrings(
            in: NSRange(location: 0, length: nsString.length),
            options: [.byParagraphs, .substringNotRequired]
        ) { _, range, enclosingRange, stop in
            // Use strict `<` so that a position at the start of paragraph N+1 doesn't
            // also match paragraph N (whose enclosing range ends at the same offset).
            let inEnclosing = location >= enclosingRange.location && location < NSMaxRange(enclosingRange)
            // Special case: cursor sitting past the very last terminator → use the last paragraph.
            let atEndOfDocument = location == nsString.length && NSMaxRange(enclosingRange) == nsString.length
            if inEnclosing || atEndOfDocument {
                found = (range, enclosingRange)
                stop.pointee = true
            }
        }
        return found
    }

    /// Insert a new empty paragraph above the current one and place the cursor in it.
    private func insertParagraphAbove() {
        guard let storage = textStorage else { return }
        let nsString = storage.string as NSString
        let sel = selectedRange()
        let paraRange = nsString.paragraphRange(for: NSRange(location: min(sel.location, nsString.length), length: 0))

        // Inherit attributes from the current paragraph.
        let probe = max(0, min(paraRange.location, storage.length - 1))
        let attrs: [NSAttributedString.Key: Any]
        if storage.length > 0 {
            attrs = storage.attributes(at: probe, effectiveRange: nil)
        } else {
            attrs = BlockAttributes.attributes(for: Block(type: .note, text: ""))
        }

        let newline = NSAttributedString(string: "\n", attributes: attrs)
        storage.beginEditing()
        storage.insert(newline, at: paraRange.location)
        storage.endEditing()

        setSelectedRange(NSRange(location: paraRange.location, length: 0))
        delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: self))
        needsDisplay = true
    }

    // MARK: Redraw checkboxes when text changes

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
        rebuildCheckboxTrackingAreas()
    }

    // MARK: Cursor — arrow over checkboxes (via NSTrackingArea)

    private var checkboxTrackingAreas: [NSTrackingArea] = []

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        rebuildCheckboxTrackingAreas()
    }

    private func rebuildCheckboxTrackingAreas() {
        for area in checkboxTrackingAreas {
            removeTrackingArea(area)
        }
        checkboxTrackingAreas.removeAll()

        for rect in checkboxRects() {
            let area = NSTrackingArea(
                rect: rect,
                options: [.cursorUpdate, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            checkboxTrackingAreas.append(area)
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        if isOverCheckbox(pt) {
            NSCursor.arrow.set()
            return
        }
        super.cursorUpdate(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        if isOverCheckbox(pt) {
            NSCursor.arrow.set()
            return
        }
        super.mouseMoved(with: event)
    }

    private func isOverCheckbox(_ point: NSPoint) -> Bool {
        checkboxRects().contains { $0.contains(point) }
    }

    private func checkboxRects() -> [NSRect] {
        // Slightly enlarge the cursor rect so the hover zone is comfortable.
        todoCheckboxEntries().map { $0.rect.insetBy(dx: -2, dy: -2) }
    }
}

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
        let scrollView = FlickEditorScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        // Reserve room at the bottom so the last line scrolls clear of the floating AddBlockBar
        // (28pt button + 8pt vertical padding + 8pt bottom margin + a little breathing room).
        // Reserve room at the top so the first line clears the 24pt edge-fade band drawn by FlickEditorScrollView.
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 18, left: 0, bottom: 52, right: 0)

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
        textView.insertionPointColor = .labelColor

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
        context.coordinator.installWindowVisibleObserver()

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
        private var windowVisibleObserver: Any?
        /// Insertion index last seen while editing; AddBlockBar taps can steal focus and move `selectedRange()` before conversion runs.
        private var caretCharIndexForBarConversion: Int = 0

        init(_ parent: FlickTextEditor) {
            self.parent = parent
        }

        deinit {
            if let conversionObserver {
                NotificationCenter.default.removeObserver(conversionObserver)
            }
            if let windowVisibleObserver {
                NotificationCenter.default.removeObserver(windowVisibleObserver)
            }
        }

        func installConversionObserver() {
            conversionObserver = NotificationCenter.default.addObserver(
                forName: .flickConvertParagraph,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self else { return }
                guard let raw = notification.object as? String,
                      let type = BlockType(rawValue: raw),
                      let textView = self.textView else { return }
                textView.convertCurrentParagraph(to: type, barAnchorLocation: self.caretCharIndexForBarConversion)
                // Conversion does not go through `textDidChange`; without a synchronous binding update,
                // `updateNSView` can run with stale `blocks` and replace the edited storage (especially on the buffer line).
                self.completeConversionEdits(in: textView)
            }
        }

        func installWindowVisibleObserver() {
            windowVisibleObserver = NotificationCenter.default.addObserver(
                forName: .flickWindowDidBecomeVisible,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self, let textView = self.textView else { return }
                textView.focusFirstLineIfPristineBlankPage()
            }
        }

        /// Replace the text view's content with the attributed string for these blocks.
        func replaceContents(with blocks: [Block], in textView: FlickTextView) {
            isApplyingProgrammaticChange = true
            defer { isApplyingProgrammaticChange = false }
            let attr = blocks.toAttributedString()
            textView.textStorage?.setAttributedString(attr)
            ensureTrailingBuffer(in: textView)
            captureCaretAnchor(from: textView)
            updateFocusedBlockType()
            DispatchQueue.main.async { [weak textView] in
                textView?.focusFirstLineIfPristineBlankPage()
            }
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingProgrammaticChange,
                  let textView = self.textView else { return }
            ensureParagraphAttributes(in: textView)
            ensureTrailingBuffer(in: textView)
            syncBlocksFromStorage()
            if textView.window?.firstResponder === textView {
                captureCaretAnchor(from: textView)
            }
            updateFocusedBlockType()
        }

        private func captureCaretAnchor(from textView: FlickTextView) {
            let len = (textView.string as NSString).length
            let loc = textView.selectedRange().location
            caretCharIndexForBarConversion = max(0, min(loc, len))
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
            if let tv = textView, tv.window?.firstResponder === tv {
                captureCaretAnchor(from: tv)
            }
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

        /// After AddBlockBar conversion: reapply paragraph attrs, restore the trailing `.note` buffer if needed, and
        /// push `blocks` / `focusedBlockType` immediately so SwiftUI does not overwrite storage from stale state.
        private func completeConversionEdits(in textView: FlickTextView) {
            ensureParagraphAttributes(in: textView)
            ensureTrailingBuffer(in: textView)
            let newBlocks = BlockParser.blocks(from: textView.attributedString())
            if !FlickTextEditor.blocksHaveSameContent(newBlocks, parent.blocks) {
                parent.blocks = newBlocks
            }
            let type = textView.currentParagraphBlockType()
            if parent.focusedBlockType != type {
                parent.focusedBlockType = type
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

// MARK: - Trailing buffer selection clamp (must run inside `setSelectedRange` so mouse tracking never paints the caret on the buffer)

fileprivate enum FlickTrailingBufferSelection {
    /// Same criteria as `Coordinator.ensureTrailingBuffer`: last paragraph is an empty `.note`.
    static func emptyNoteBufferRange(for textView: NSTextView) -> NSRange? {
        guard let storage = textView.textStorage else { return nil }
        let nsString = storage.string as NSString
        let length = nsString.length
        guard length > 0 else { return nil }
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
        guard textLength == 0, type == .note else { return nil }
        return lastParaRange
    }

    /// Maps any selection overlapping the buffer (or EOF past it) onto the last real paragraph; trims drags at the buffer boundary.
    static func clampedRange(_ range: NSRange, for textView: NSTextView) -> NSRange {
        guard let bufRange = emptyNoteBufferRange(for: textView) else { return range }
        let bufStart = bufRange.location
        let len = (textView.string as NSString).length
        guard bufStart > 0 else { return range }
        let target = bufStart - 1

        let a = range.location
        let b = a + range.length

        if range.length == 0 {
            if a >= bufStart && a <= len { return NSRange(location: target, length: 0) }
            return range
        }
        if b <= bufStart { return range }
        if a >= bufStart { return NSRange(location: target, length: 0) }
        return NSRange(location: a, length: bufStart - a)
    }
}

// MARK: - NSTextView subclass

final class FlickTextView: NSTextView {
    override var acceptsFirstResponder: Bool { true }

    override func setSelectedRange(_ charRange: NSRange, affinity: NSSelectionAffinity, stillSelecting stillSelectingFlag: Bool) {
        let clamped = FlickTrailingBufferSelection.clampedRange(charRange, for: self)
        if NSEqualRanges(clamped, charRange) {
            super.setSelectedRange(charRange, affinity: affinity, stillSelecting: stillSelectingFlag)
        } else {
            super.setSelectedRange(clamped, affinity: affinity, stillSelecting: stillSelectingFlag)
        }
    }

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
        drawEmptyPagePlaceholderIfNeeded(in: dirtyRect)
        drawCheckboxes(in: dirtyRect)
    }

    // MARK: Empty page placeholder (first line)

    private static let emptyPagePlaceholderString = "write something…"
    /// Fine-tune vs real text baseline/origin (drawn placeholder vs TextKit line fragment).
    private static let emptyPagePlaceholderDrawOffset = CGSize(width: -8, height: -9)

    /// True for a pristine empty **note** page: no visible text, only `.note` blocks (after stripping the trailing buffer), ≤2 paragraphs. Title/todo or extra newlines hide it.
    private func shouldShowEmptyPagePlaceholder() -> Bool {
        guard string.allSatisfy(\.isWhitespace) else { return false }

        var content = BlockParser.blocks(from: attributedString())
        while content.count > 1,
              let last = content.last,
              last.type == .note,
              last.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            content.removeLast()
        }
        guard content.allSatisfy({ $0.type == .note }) else { return false }

        let ns = string as NSString
        if ns.length == 0 { return true }
        var paragraphCount = 0
        ns.enumerateSubstrings(
            in: NSRange(location: 0, length: ns.length),
            options: [.byParagraphs, .substringNotRequired]
        ) { _, _, _, _ in
            paragraphCount += 1
        }
        return paragraphCount <= 2
    }

    private func drawEmptyPagePlaceholderIfNeeded(in dirtyRect: NSRect) {
        guard shouldShowEmptyPagePlaceholder() else { return }
        guard let lm = layoutManager, let tc = textContainer else { return }

        let ns = string as NSString
        let length = ns.length
        let font = BlockAttributes.font(for: .note)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor.withAlphaComponent(0.5)
        ]
        let attrStr = NSAttributedString(string: Self.emptyPagePlaceholderString, attributes: attrs)

        let drawRect: NSRect
        if length == 0 {
            let lineHeight = lm.defaultLineHeight(for: font)
            drawRect = NSRect(
                x: textContainerOrigin.x + textContainerInset.width,
                y: textContainerOrigin.y + textContainerInset.height,
                width: max(1, tc.size.width),
                height: lineHeight
            )
        } else {
            let firstPara = ns.paragraphRange(for: NSRange(location: 0, length: 0))
            lm.ensureGlyphs(forCharacterRange: NSRange(location: 0, length: length))
            lm.ensureLayout(forCharacterRange: NSRange(location: 0, length: length))
            guard let lc = paragraphLineRect(for: firstPara, length: length, layoutManager: lm, textContainer: tc) else { return }
            drawRect = NSRect(
                x: textContainerOrigin.x + textContainerInset.width + lc.minX,
                y: textContainerOrigin.y + textContainerInset.height + lc.minY,
                width: max(1, lc.width),
                height: lc.height
            )
        }

        let adjusted = drawRect.offsetBy(
            dx: Self.emptyPagePlaceholderDrawOffset.width,
            dy: Self.emptyPagePlaceholderDrawOffset.height
        )
        guard adjusted.intersects(dirtyRect) else { return }
        attrStr.draw(with: adjusted, options: [.usesLineFragmentOrigin, .usesFontLeading])
    }

    /// Makes the editor key with the caret on the first line when the document is still a pristine blank page.
    func focusFirstLineIfPristineBlankPage() {
        guard shouldShowEmptyPagePlaceholder() else { return }
        guard let win = window, win.isVisible else { return }
        win.makeFirstResponder(self)
        setSelectedRange(NSRange(location: 0, length: 0))
    }

    private func drawCheckboxes(in dirtyRect: NSRect) {
        let now = CACurrentMediaTime()
        for entry in todoCheckboxEntries() {
            guard entry.rect.intersects(dirtyRect) else { continue }
            let fraction: CGFloat
            if let anim = currentAnimation(forParagraph: entry.paragraphLocation) {
                fraction = animationFraction(for: anim, now: now)
            } else {
                fraction = entry.checked ? 1 : 0
            }
            drawCheckbox(in: entry.rect, fraction: fraction)
        }
    }

    /// Walks line fragments and produces one checkbox entry per todo paragraph at the
    /// y-position of the paragraph's first line.
    private func todoCheckboxEntries() -> [(rect: NSRect, checked: Bool, paragraphLocation: Int)] {
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
        var entries: [(rect: NSRect, checked: Bool, paragraphLocation: Int)] = []

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
            entries.append((
                NSRect(x: x, y: y, width: size, height: size),
                checked,
                paragraphStart
            ))
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

    /// Draws the checkbox at an interpolated state. `fraction` is 0 (unchecked) → 1 (fully checked).
    private func drawCheckbox(in rect: NSRect, fraction rawFraction: CGFloat) {
        let f = max(0, min(1, rawFraction))
        let path = NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
        path.lineWidth = 1.2

        if f > 0 {
            NSColor.labelColor.withAlphaComponent(0.85 * f).setFill()
            path.fill()
        }
        // Two stacked strokes blend tertiary → label as f goes 0 → 1.
        if f < 1 {
            NSColor.tertiaryLabelColor.withAlphaComponent(1 - f).setStroke()
            path.stroke()
        }
        if f > 0 {
            NSColor.labelColor.withAlphaComponent(f).setStroke()
            path.stroke()
        }

        if f > 0 {
            drawCheckmark(in: rect, fraction: f)
        }
    }

    /// Draws a partial check-mark polyline (NSTextView is flipped: minY = top, maxY = bottom).
    private func drawCheckmark(in rect: NSRect, fraction: CGFloat) {
        let inset = rect.insetBy(dx: 3, dy: 3.5)
        let p0 = NSPoint(x: inset.minX, y: inset.midY)
        let p1 = NSPoint(x: inset.midX - 0.5, y: inset.maxY)
        let p2 = NSPoint(x: inset.maxX, y: inset.minY + 1)
        let len1 = hypot(p1.x - p0.x, p1.y - p0.y)
        let len2 = hypot(p2.x - p1.x, p2.y - p1.y)
        let total = len1 + len2
        let want = max(0, total * fraction)

        let path = NSBezierPath()
        path.move(to: p0)
        if want <= len1 || total <= 0 {
            let t = len1 > 0 ? want / len1 : 0
            path.line(to: NSPoint(x: p0.x + (p1.x - p0.x) * t, y: p0.y + (p1.y - p0.y) * t))
        } else {
            path.line(to: p1)
            let r = len2 > 0 ? (want - len1) / len2 : 0
            path.line(to: NSPoint(x: p1.x + (p2.x - p1.x) * r, y: p1.y + (p2.y - p1.y) * r))
        }
        path.lineWidth = 1.4
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        NSColor.windowBackgroundColor.setStroke()
        path.stroke()
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

        // Apply final attributes (including system strikethrough) immediately. We only animate the
        // checkbox tick; the strike-through flips instantly with the rest of the paragraph attrs.
        let block = Block(type: .todo, text: "", isChecked: newChecked)
        let attrs = BlockAttributes.attributes(for: block)

        // NSString.paragraphRange(for:) already includes the trailing terminator —
        // do NOT expand further or we'll set attributes on the next paragraph too.
        storage.beginEditing()
        if paragraphRange.length > 0 {
            storage.setAttributes(attrs, range: paragraphRange)
        }
        storage.endEditing()

        // Sync the SwiftUI binding right away.
        delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: self))

        // Animate just the checkbox tick.
        startCheckboxAnimation(paragraphRange: paragraphRange, toChecked: newChecked)
    }

    // MARK: Block conversion (called by AddBlockBar via notification)

    func convertCurrentParagraph(to newType: BlockType, barAnchorLocation: Int? = nil) {
        guard let storage = textStorage else { return }
        let nsString = storage.string as NSString
        guard nsString.length > 0 else { return }
        let anchor = barAnchorLocation ?? selectedRange().location
        // `paragraphRange(for:)` + `len - 1` can attribute the *previous* paragraph at EOF; use the same
        // boundary rules as `demoteEmptyTitleOrTodoToNote` (strict `<` + `atEndOfDocument`).
        guard let (_, paraRange) = paragraphRanges(at: anchor, in: nsString) else { return }

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
        let nsString = storage.string as NSString
        guard let (_, enclosing) = paragraphRanges(at: sel.location, in: nsString) else { return nil }
        let probe = max(0, min(enclosing.location, storage.length - 1))
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

        let shouldMakeNextLineNote = shouldInsertNoteAfterTitleReturn()
        super.insertNewline(sender)

        if shouldMakeNextLineNote {
            applyNoteAttributesToParagraph(at: selectedRange().location)
            delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: self))
            needsDisplay = true
            rebuildCheckboxTrackingAreas()
        }
    }

    /// Plain Return on a non-empty title paragraph → new line should be a normal (`.note`) paragraph.
    private func shouldInsertNoteAfterTitleReturn() -> Bool {
        guard let storage = textStorage else { return false }
        let nsString = storage.string as NSString
        let sel = selectedRange()
        guard sel.length == 0 else { return false }

        let paraRange = nsString.paragraphRange(for: NSRange(location: min(sel.location, nsString.length), length: 0))
        let probe = max(0, min(paraRange.location, storage.length - 1))
        let attrs = storage.attributes(at: probe, effectiveRange: nil)
        guard let raw = attrs[.flickBlockType] as? String,
              let type = BlockType(rawValue: raw),
              type == .title else { return false }

        let endContent = NSMaxRange(paraRange) - 1
        guard endContent >= paraRange.location else { return false }
        let contentRange = NSRange(location: paraRange.location, length: endContent - paraRange.location)
        let slice = (contentRange.length > 0 ? nsString.substring(with: contentRange) : "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return !slice.isEmpty
    }

    /// Re-types the paragraph containing `characterIndex` as an empty `.note` paragraph (including its `\n`).
    private func applyNoteAttributesToParagraph(at characterIndex: Int) {
        guard let storage = textStorage else { return }
        let nsString = storage.string as NSString
        guard nsString.length > 0 else { return }
        let idx = min(characterIndex, nsString.length)
        let paraRange = nsString.paragraphRange(for: NSRange(location: idx, length: 0))
        let block = Block(type: .note, text: "", isChecked: false)
        let attrs = BlockAttributes.attributes(for: block)
        storage.beginEditing()
        if paraRange.length > 0 {
            storage.setAttributes(attrs, range: paraRange)
        }
        typingAttributes = attrs
        storage.endEditing()
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

    /// Paragraph bounds for Flick: same construction as `Coordinator.ensureParagraphAttributes` —
    /// each logical paragraph is `substring` (from `enumerateSubstrings`) plus **at most one** following `\n`.
    ///
    /// Apple's `enclosingRange` is **not** used here: it can span **both** `\n` in `…text\n\n` (content + empty buffer),
    /// so `setAttributes` on that range re-types the **content** line when you meant the buffer.
    private func paragraphRanges(at location: Int, in nsString: NSString) -> (sub: NSRange, enclosing: NSRange)? {
        let len = nsString.length
        guard len > 0 else { return nil }

        var subs: [NSRange] = []
        nsString.enumerateSubstrings(
            in: NSRange(location: 0, length: len),
            options: [.byParagraphs, .substringNotRequired]
        ) { _, sub, _, _ in
            subs.append(sub)
        }
        guard !subs.isEmpty else { return nil }

        let fullRanges: [NSRange] = subs.map { sub -> NSRange in
            var full = sub
            if NSMaxRange(full) < len,
               nsString.substring(with: NSRange(location: NSMaxRange(full), length: 1)) == "\n" {
                full.length += 1
            }
            return full
        }

        let lastIdx = subs.count - 1
        let result: (NSRange, NSRange)
        if location >= len {
            result = (subs[lastIdx], fullRanges[lastIdx])
        } else {
            var matchIndices: [Int] = []
            for i in 0..<fullRanges.count {
                let full = fullRanges[i]
                if location >= full.location && location < NSMaxRange(full) {
                    matchIndices.append(i)
                }
            }
            if let idx = matchIndices.last {
                result = (subs[idx], fullRanges[idx])
            } else {
                result = (subs[lastIdx], fullRanges[lastIdx])
            }
        }
        return result
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
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            self?.focusFirstLineIfPristineBlankPage()
        }
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

    // MARK: - Checkbox toggle animation engine

    private struct CheckboxAnimation {
        let start: CFTimeInterval
        let duration: CFTimeInterval
        let toChecked: Bool
        let paragraphRange: NSRange
    }

    private static let checkboxAnimationDuration: CFTimeInterval = 0.28

    private var checkboxAnimations: [CheckboxAnimation] = []
    private var checkboxAnimationTimer: Timer?

    private func currentAnimation(forParagraph location: Int) -> CheckboxAnimation? {
        checkboxAnimations.last(where: { $0.paragraphRange.location == location })
    }

    private func animationFraction(for anim: CheckboxAnimation, now: CFTimeInterval) -> CGFloat {
        let raw = max(0, min(1, (now - anim.start) / anim.duration))
        let eased = Self.easeOutCubic(CGFloat(raw))
        return anim.toChecked ? eased : (1 - eased)
    }

    private static func easeOutCubic(_ t: CGFloat) -> CGFloat {
        1 - pow(1 - t, 3)
    }

    private func startCheckboxAnimation(paragraphRange: NSRange, toChecked: Bool) {
        // Latest tap on the same paragraph supersedes any in-flight animation.
        checkboxAnimations.removeAll { $0.paragraphRange.location == paragraphRange.location }
        let anim = CheckboxAnimation(
            start: CACurrentMediaTime(),
            duration: Self.checkboxAnimationDuration,
            toChecked: toChecked,
            paragraphRange: paragraphRange
        )
        checkboxAnimations.append(anim)
        startCheckboxAnimationTimer()
        invalidateParagraphRect(for: paragraphRange)
    }

    private func startCheckboxAnimationTimer() {
        guard checkboxAnimationTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tickCheckboxAnimations()
        }
        RunLoop.main.add(timer, forMode: .common)
        checkboxAnimationTimer = timer
    }

    private func stopCheckboxAnimationTimerIfIdle() {
        guard checkboxAnimations.isEmpty else { return }
        checkboxAnimationTimer?.invalidate()
        checkboxAnimationTimer = nil
    }

    private func tickCheckboxAnimations() {
        let now = CACurrentMediaTime()
        var stillRunning: [CheckboxAnimation] = []
        var completed: [CheckboxAnimation] = []
        for anim in checkboxAnimations {
            if now - anim.start >= anim.duration {
                completed.append(anim)
            } else {
                stillRunning.append(anim)
            }
        }
        checkboxAnimations = stillRunning
        for anim in completed {
            finalizeCheckboxAnimation(anim)
        }
        // Repaint each in-flight paragraph's region so the next display cycle reflects the new fraction.
        for anim in checkboxAnimations {
            invalidateParagraphRect(for: anim.paragraphRange)
        }
        stopCheckboxAnimationTimerIfIdle()
    }

    private func finalizeCheckboxAnimation(_ anim: CheckboxAnimation) {
        // Storage is already in its final state (set in `toggleTodoChecked`); the animation is
        // purely a draw-time effect, so we just request a final repaint of the paragraph.
        invalidateParagraphRect(for: anim.paragraphRange)
    }

    private func invalidateParagraphRect(for paraRange: NSRange) {
        if let rect = paragraphInvalidationRect(for: paraRange) {
            setNeedsDisplay(rect)
        } else {
            needsDisplay = true
        }
    }

    /// Bounding rect of the paragraph's visible content (checkbox column + line fragments) in view coords.
    private func paragraphInvalidationRect(for paraRange: NSRange) -> NSRect? {
        guard let layoutManager = layoutManager,
              let storage = textStorage else { return nil }
        let length = storage.length
        let safeRange = NSRange(
            location: max(0, min(paraRange.location, length)),
            length: max(0, min(paraRange.length, length - paraRange.location))
        )
        guard safeRange.length > 0 else { return nil }
        let glyphRange = layoutManager.glyphRange(forCharacterRange: safeRange, actualCharacterRange: nil)
        var union = NSRect.zero
        var first = true
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { lineRect, _, _, _, _ in
            let inView = NSRect(
                x: 0,
                y: lineRect.minY + self.textContainerInset.height,
                width: max(self.bounds.width, lineRect.maxX + self.textContainerInset.width),
                height: lineRect.height
            )
            union = first ? inView : union.union(inView)
            first = false
        }
        guard !first else { return nil }
        return union.insetBy(dx: -2, dy: -2)
    }

}

// MARK: - NSScrollView subclass with viewport edge fade

/// `NSScrollView` that softly fades content at its top and bottom via a `CAGradientLayer` mask
/// pinned to the visible viewport. The mask sits on the scroll view's own layer so it never moves
/// with the scrolled content, and it doesn't affect hit testing — clicks on checkboxes still work
/// in the faded bands.
final class FlickEditorScrollView: NSScrollView {
    /// Height of each fade band, in points.
    private let fadeHeight: CGFloat = 24
    private let fadeMask = CAGradientLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupFadeMask()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupFadeMask()
    }

    private func setupFadeMask() {
        wantsLayer = true
        fadeMask.colors = [
            NSColor.clear.cgColor,
            NSColor.black.cgColor,
            NSColor.black.cgColor,
            NSColor.clear.cgColor
        ]
        fadeMask.startPoint = CGPoint(x: 0.5, y: 0)
        fadeMask.endPoint = CGPoint(x: 0.5, y: 1)
        layer?.mask = fadeMask
        updateFadeMask()
    }

    override func tile() {
        super.tile()
        updateFadeMask()
    }

    override func layout() {
        super.layout()
        updateFadeMask()
    }

    private func updateFadeMask() {
        // Disable implicit animation so the mask never lags during resize/scroll.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fadeMask.frame = bounds
        let height = max(bounds.height, 1)
        let stop = min(0.49, fadeHeight / height)
        fadeMask.locations = [
            0,
            NSNumber(value: Float(stop)),
            NSNumber(value: Float(1 - stop)),
            1
        ]
        CATransaction.commit()
    }
}

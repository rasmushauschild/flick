import AppKit

extension NSAttributedString.Key {
    static let flickBlockType = NSAttributedString.Key("FlickBlockType")
    static let flickIsChecked = NSAttributedString.Key("FlickIsChecked")
}

extension Notification.Name {
    static let flickConvertParagraph = Notification.Name("flickConvertParagraph")
    /// Posted when the Flick panel is ordered on-screen (menu-bar show, etc.) so the UI can reset the date scrubber.
    static let flickWindowDidBecomeVisible = Notification.Name("flickWindowDidBecomeVisible")
}

enum BlockAttributes {
    /// Horizontal space reserved at the leading edge of todo paragraphs for the checkbox.
    static let todoIndent: CGFloat = 22

    static let titleFont: NSFont = {
        if let font = NSFont(name: "Inter-SemiBold", size: 24) {
            return font
        }
        return NSFont.systemFont(ofSize: 24, weight: .semibold)
    }()

    static let bodyFont: NSFont = {
        if let font = NSFont(name: "Inter-Regular", size: 15) {
            return font
        }
        return NSFont.systemFont(ofSize: 15)
    }()

    static func font(for type: BlockType) -> NSFont {
        switch type {
        case .title: return titleFont
        case .note, .todo: return bodyFont
        }
    }

    static func paragraphStyle(for type: BlockType) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        switch type {
        case .title:
            style.paragraphSpacingBefore = 8
            style.paragraphSpacing = 4
        case .note:
            style.paragraphSpacingBefore = 2
            style.paragraphSpacing = 2
        case .todo:
            style.paragraphSpacingBefore = 2
            style.paragraphSpacing = 2
            style.headIndent = todoIndent
            style.firstLineHeadIndent = todoIndent
        }
        return style
    }

    /// Returns the attributes that should apply to all characters in a block's paragraph.
    static func attributes(for block: Block) -> [NSAttributedString.Key: Any] {
        var attrs: [NSAttributedString.Key: Any] = [
            .flickBlockType: block.type.rawValue,
            .flickIsChecked: block.isChecked,
            .font: font(for: block.type),
            .paragraphStyle: paragraphStyle(for: block.type),
            .foregroundColor: NSColor.labelColor
        ]
        if block.type == .todo && block.isChecked {
            attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            attrs[.foregroundColor] = NSColor.tertiaryLabelColor
        }
        return attrs
    }
}

extension Array where Element == Block {
    /// Render the blocks as a single attributed string. One paragraph per block, joined by "\n".
    /// The text is just the user's content — checkboxes are drawn separately by the text view.
    func toAttributedString() -> NSAttributedString {
        let result = NSMutableAttributedString()
        for block in self {
            let para = block.text + "\n"
            let start = result.length
            result.append(NSAttributedString(string: para))
            let range = NSRange(location: start, length: (para as NSString).length)
            result.addAttributes(BlockAttributes.attributes(for: block), range: range)
        }
        return result
    }
}

enum BlockParser {
    /// Convert an attributed string back to the [Block] model.
    /// Each paragraph (split by "\n") becomes one block; type/checked are read from the first character's attributes.
    static func blocks(from attr: NSAttributedString) -> [Block] {
        let nsString = attr.string as NSString
        if nsString.length == 0 {
            return [Block(type: .note, text: "")]
        }

        var blocks: [Block] = []
        var paragraphRanges: [NSRange] = []
        nsString.enumerateSubstrings(
            in: NSRange(location: 0, length: nsString.length),
            options: [.byParagraphs, .substringNotRequired]
        ) { _, range, _, _ in
            paragraphRanges.append(range)
        }

        for range in paragraphRanges {
            let probeIndex = max(0, min(range.location, attr.length - 1))
            guard probeIndex >= 0, attr.length > 0 else { continue }
            let attrs = attr.attributes(at: probeIndex, effectiveRange: nil)

            let typeRaw = (attrs[.flickBlockType] as? String) ?? BlockType.note.rawValue
            let type = BlockType(rawValue: typeRaw) ?? .note
            let isChecked = (attrs[.flickIsChecked] as? Bool) ?? false

            let text = nsString.substring(with: range)
            blocks.append(Block(type: type, text: text, isChecked: isChecked))
        }

        if blocks.isEmpty {
            blocks.append(Block(type: .note, text: ""))
        }
        return blocks
    }
}

import SwiftUI
import AppKit

struct PageView: View {
    @Environment(Store.self) private var store
    let mode: PageMode

    @State private var blocks: [Block] = []
    @State private var pageID: String = ""
    @State private var focusedBlockType: BlockType? = nil

    var body: some View {
        VStack(spacing: 0) {
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
        }
        .onAppear { reload() }
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

import SwiftUI
import AppKit

struct BlockFramesKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct PageView: View {
    @Environment(Store.self) private var store
    let selectedDate: Date

    @State private var blocks: [Block] = []
    @State private var pageID: String = ""
    @FocusState private var focusedID: UUID?
    @State private var selectedBlockIDs: Set<UUID> = []
    @State private var blockFrames: [UUID: CGRect] = [:]
    @State private var dragStart: CGPoint?
    @State private var dragSelectionActive = false

    private var focusedBlockType: BlockType? {
        guard let id = focusedID else { return nil }
        return blocks.first { $0.id == id }?.type
    }

    private var isFreshDay: Bool {
        blocks.count == 1 && (blocks.first?.text.isEmpty ?? false)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(blocks) { block in
                            BlockRow(
                                block: binding(for: block.id),
                                focusedID: $focusedID,
                                isSelected: selectedBlockIDs.contains(block.id),
                                customPlaceholder: (block.id == blocks.first?.id && isFreshDay) ? "What are we doing today?" : nil,
                                onSubmit: { insertBlock(after: block.id) },
                                onInsertAbove: { insertBlock(before: block.id) },
                                onDelete: { deleteBlock(id: block.id) },
                                onMoveUp: { moveFocus(from: block.id, by: -1) },
                                onMoveDown: { moveFocus(from: block.id, by: 1) },
                                onShiftClick: { extendSelection(to: block.id) },
                                onCommandClick: { toggleSelection(of: block.id) }
                            )
                            .id(block.id)
                            .background(
                                GeometryReader { geo in
                                    Color.clear.preference(
                                        key: BlockFramesKey.self,
                                        value: [block.id: geo.frame(in: .global)]
                                    )
                                }
                            )
                        }
                    }
                    .padding(.vertical, 8)
                }
                .contentShape(Rectangle())
                .onPreferenceChange(BlockFramesKey.self) { frames in
                    blockFrames = frames
                }
                .onTapGesture {
                    selectedBlockIDs.removeAll()
                    if let lastID = blocks.last?.id {
                        focusedID = lastID
                    }
                }
                .onChange(of: focusedID) { _, id in
                    if let id {
                        if !dragSelectionActive { selectedBlockIDs.removeAll() }
                        withAnimation { proxy.scrollTo(id, anchor: .bottom) }
                        let collapse = {
                            if let editor = NSApp.keyWindow?.firstResponder as? NSTextView {
                                let len = (editor.string as NSString).length
                                editor.setSelectedRange(NSRange(location: len, length: 0))
                            }
                        }
                        collapse()
                        DispatchQueue.main.async(execute: collapse)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .flickBackspacePressed)) { _ in
                    guard !selectedBlockIDs.isEmpty else { return }
                    deleteSelectedBlocks()
                }
            }

            AddBlockBar(
                focusedBlockType: focusedBlockType,
                onConvert: convertFocusedBlock
            )
        }
        .onAppear { reload() }
        .onChange(of: blocks) { save() }
    }

    private func handleDragSelection(start: CGPoint, current: CGPoint) {
        let minY = min(start.y, current.y)
        let maxY = max(start.y, current.y)
        let coveredIDs = blockFrames.compactMap { id, frame -> UUID? in
            (frame.maxY >= minY && frame.minY <= maxY) ? id : nil
        }
        if coveredIDs.count >= 2 || dragSelectionActive {
            dragSelectionActive = true
            focusedID = nil
            selectedBlockIDs = Set(coveredIDs)
        }
    }

    private func binding(for id: UUID) -> Binding<Block> {
        Binding(
            get: { blocks.first(where: { $0.id == id }) ?? Block(type: .note, text: "") },
            set: { newValue in
                if let idx = blocks.firstIndex(where: { $0.id == id }) {
                    blocks[idx] = newValue
                }
            }
        )
    }

    private func reload() {
        let page = store.page(for: selectedDate)
        pageID = page.id
        if page.blocks.isEmpty {
            let starter = Block(type: .note, text: "")
            blocks = [starter]
            let id = starter.id
            Task { focusedID = id }
        } else {
            blocks = page.blocks
        }
    }

    private func save() {
        guard blocks.contains(where: { !$0.text.isEmpty }) else { return }
        store.update(DayPage(id: pageID, blocks: blocks))
    }

    private func insertBlock(after id: UUID) {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
        let sourceType = blocks[index].type
        let newType: BlockType = sourceType == .title ? .note : sourceType
        let newBlock = Block(type: newType, text: "")
        blocks.insert(newBlock, at: index + 1)
        let newID = newBlock.id
        Task { focusedID = newID }
    }

    private func insertBlock(before id: UUID) {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
        let sourceType = blocks[index].type
        let newType: BlockType = sourceType == .title ? .note : sourceType
        let newBlock = Block(type: newType, text: "")
        blocks.insert(newBlock, at: index)
        let newID = newBlock.id
        Task { focusedID = newID }
    }

    private func deleteBlock(id: UUID) {
        guard blocks.count > 1,
              let index = blocks.firstIndex(where: { $0.id == id }) else { return }
        let fallbackID = index > 0 ? blocks[index - 1].id : blocks[1].id
        focusedID = fallbackID
        DispatchQueue.main.async {
            blocks.removeAll { $0.id == id }
        }
    }

    private func deleteSelectedBlocks() {
        let toDelete = selectedBlockIDs
        selectedBlockIDs.removeAll()

        let firstDeletedIndex = blocks.firstIndex(where: { toDelete.contains($0.id) }) ?? 0
        let remaining = blocks.filter { !toDelete.contains($0.id) }
        let fallbackID = remaining.indices.contains(max(0, firstDeletedIndex - 1))
            ? remaining[max(0, firstDeletedIndex - 1)].id
            : remaining.first?.id

        if remaining.isEmpty {
            let starter = Block(type: .note, text: "")
            blocks = [starter]
            let id = starter.id
            Task { focusedID = id }
        } else {
            blocks = remaining
            if let fallbackID {
                Task { focusedID = fallbackID }
            }
        }
    }

    private func moveFocus(from id: UUID, by offset: Int) {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard target >= 0 && target < blocks.count else { return }
        focusedID = blocks[target].id
    }

    private func convertFocusedBlock(to newType: BlockType) {
        guard let id = focusedID,
              let index = blocks.firstIndex(where: { $0.id == id }) else { return }
        blocks[index].type = newType
    }

    private func toggleSelection(of id: UUID) {
        if selectedBlockIDs.contains(id) {
            selectedBlockIDs.remove(id)
        } else {
            selectedBlockIDs.insert(id)
        }
    }

    private func extendSelection(to id: UUID) {
        guard let endIndex = blocks.firstIndex(where: { $0.id == id }) else { return }
        let anchorIndex: Int
        if let focused = focusedID,
           let idx = blocks.firstIndex(where: { $0.id == focused }) {
            anchorIndex = idx
        } else if let first = selectedBlockIDs.compactMap({ id in
            blocks.firstIndex(where: { $0.id == id })
        }).min() {
            anchorIndex = first
        } else {
            anchorIndex = endIndex
        }
        let lo = min(anchorIndex, endIndex)
        let hi = max(anchorIndex, endIndex)
        selectedBlockIDs = Set(blocks[lo...hi].map { $0.id })
    }
}

import Foundation

enum BlockType: String, Codable {
    case title, note, todo
}

struct Block: Identifiable, Codable, Equatable {
    var id = UUID()
    var type: BlockType
    var text: String
    var isChecked: Bool = false
}

import Foundation

struct DayPage: Identifiable, Codable, Equatable {
    var id: String   // "yyyy-MM-dd"
    var blocks: [Block] = []
}

import Foundation
import Observation

@Observable
class Store {
    var pages: [String: DayPage] = [:]

    private let fileURL: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("Flick", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("pages.json")
        load()
    }

    func page(for date: Date) -> DayPage {
        let key = Self.key(for: date)
        return pages[key] ?? DayPage(id: key)
    }

    func hasContent(for date: Date) -> Bool {
        let key = Self.key(for: date)
        return pages[key]?.blocks.contains(where: { !$0.text.isEmpty }) ?? false
    }

    func update(_ page: DayPage) {
        pages[page.id] = page
        save()
    }

    static func key(for date: Date) -> String {
        date.formatted(.iso8601.year().month().day())
    }

    private func load() {
        guard
            let data = try? Data(contentsOf: fileURL),
            let decoded = try? JSONDecoder().decode([String: DayPage].self, from: data)
        else { return }
        pages = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(pages) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

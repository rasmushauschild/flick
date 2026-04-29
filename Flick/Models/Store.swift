import Foundation
import Observation

enum PageMode: Equatable, Hashable {
    case daily(Date)
    case permanent

    var storageID: String {
        switch self {
        case .daily(let date): return Store.key(for: date)
        case .permanent: return Store.permanentKey
        }
    }
}

@Observable
class Store {
    var pages: [String: DayPage] = [:]

    private let fileURL: URL

    init() {
        let isUITesting = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        let baseDir: URL
        if isUITesting {
            // Use an isolated, ephemeral location so tests start with a clean store.
            baseDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("FlickUITests-\(UUID().uuidString)", isDirectory: true)
        } else {
            baseDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("Flick", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        fileURL = baseDir.appendingPathComponent("pages.json")
        load()
    }

    func page(for mode: PageMode) -> DayPage {
        let key = mode.storageID
        return pages[key] ?? DayPage(id: key)
    }

    func page(for date: Date) -> DayPage {
        page(for: .daily(date))
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

    static let permanentKey = "__permanent__"

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

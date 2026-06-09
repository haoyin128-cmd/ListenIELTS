import Foundation

/// 历史记录条目
struct HistoryEntry: Codable, Identifiable {
    let id: UUID
    let url: URL
    let isFolder: Bool
    let addedAt: Date

    var displayName: String { url.lastPathComponent }

    init(url: URL, isFolder: Bool) {
        self.id = UUID()
        self.url = url
        self.isFolder = isFolder
        self.addedAt = Date()
    }
}

/// 历史记录管理器（最多保留20条）
@MainActor
final class HistoryManager: ObservableObject {
    static let shared = HistoryManager()

    @Published var entries: [HistoryEntry] = []

    private let key = "history.entries"
    private let maxCount = 20

    nonisolated init() {}

    func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data)
        else { return }
        entries = decoded
    }

    func record(url: URL, isFolder: Bool) {
        // 已存在则移到最前
        entries.removeAll { $0.url == url }
        entries.insert(HistoryEntry(url: url, isFolder: isFolder), at: 0)
        if entries.count > maxCount { entries = Array(entries.prefix(maxCount)) }
        save()
    }

    func remove(_ entry: HistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func clearAll() {
        entries.removeAll()
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

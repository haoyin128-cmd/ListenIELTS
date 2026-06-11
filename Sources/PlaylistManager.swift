import Foundation
import AppKit
import UniformTypeIdentifiers

/// 排序方式
enum SortOrder: String, CaseIterable {
    case manual       = "手动排序"
    case nameAsc      = "文件名 A→Z"
    case nameDesc     = "文件名 Z→A"
    case addedNewest  = "最新添加"
    case addedOldest  = "最早添加"
}

/// 播放列表管理器 —— 负责文件扫描、曲目管理、持久化
@MainActor
final class PlaylistManager: ObservableObject {
    @Published var tracks: [TrackItem] = []
    @Published var currentIndex: Int? = nil
    /// 当前排序方式（用于 UI 显示与持久化）
    @Published var currentSortOrder: SortOrder = .nameAsc
    /// 当前打开的文件夹（用于排序记忆 key）
    @Published var currentFolder: URL? = nil

    static let supportedExtensions: Set<String> = ["mp3", "m4a", "wav", "aac", "flac", "aiff", "aif", "ogg", "wma"]

    private let tracksKey = "playlist.tracks"
    private let folderKey = "playlist.currentFolder"
    private let restoreKey = "playlist.autoRestore"
    private let sortPrefix = "playlist.sort."        // + folder path
    private let progressPrefix = "playlist.progress." // + folder path
    private let prefsPrefix = "playlist.prefs."     // + folder path → {rate, mode}

    var autoRestore: Bool {
        get { UserDefaults.standard.object(forKey: restoreKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: restoreKey) }
    }

    /// 读取某文件夹的记忆排序方式（默认 A→Z）
    func savedSortOrder(for folder: URL?) -> SortOrder {
        guard let folder else { return .nameAsc }
        let key = sortPrefix + folder.path
        if let raw = UserDefaults.standard.string(forKey: key),
           let order = SortOrder(rawValue: raw) {
            return order
        }
        return .nameAsc
    }

    /// 记住某文件夹的排序方式
    private func saveSortOrder(_ order: SortOrder, for folder: URL?) {
        guard let folder else { return }
        UserDefaults.standard.set(order.rawValue, forKey: sortPrefix + folder.path)
    }

    // MARK: - Per-Folder Progress Memory

    /// 保存某文件夹的播放进度（曲目路径 + 秒数）
    func saveProgress(folder: URL?, trackURL: URL, time: TimeInterval) {
        guard let folder else { return }
        let key = progressPrefix + folder.path
        UserDefaults.standard.set([
            "track": trackURL.path,
            "time": time
        ], forKey: key)
    }

    /// 读取某文件夹上次的播放进度
    func loadProgress(folder: URL?) -> (track: TrackItem, time: TimeInterval)? {
        guard let folder else { return nil }
        let key = progressPrefix + folder.path
        guard let dict = UserDefaults.standard.dictionary(forKey: key),
              let trackPath = dict["track"] as? String,
              let time = dict["time"] as? TimeInterval,
              let track = tracks.first(where: { $0.url.path == trackPath })
        else { return nil }
        return (track, time)
    }

    // MARK: - Per-Folder Preferences (rate / play mode)

    /// 保存某文件夹的播放偏好（速度 + 模式）
    func savePrefs(folder: URL?, rate: Float, mode: PlayMode) {
        guard let folder else { return }
        let key = prefsPrefix + folder.path
        UserDefaults.standard.set([
            "rate": rate,
            "mode": mode.rawValue
        ], forKey: key)
    }

    /// 读取某文件夹的播放偏好（默认 1.0x + 顺序播放）
    func loadPrefs(folder: URL?) -> (rate: Float, mode: PlayMode) {
        guard let folder,
              let dict = UserDefaults.standard.dictionary(forKey: prefsPrefix + folder.path)
        else { return (1.0, .sequential) }
        let rate = (dict["rate"] as? Double).map { Float($0) } ?? 1.0
        let mode = (dict["mode"] as? String).flatMap { PlayMode(rawValue: $0) } ?? .sequential
        return (rate, mode)
    }

    var currentTrack: TrackItem? {
        guard let idx = currentIndex, tracks.indices.contains(idx) else { return nil }
        return tracks[idx]
    }

    var hasNext: Bool {
        guard let idx = currentIndex else { return !tracks.isEmpty }
        return idx + 1 < tracks.count
    }

    var hasPrevious: Bool {
        guard let idx = currentIndex else { return false }
        return idx > 0
    }

    // MARK: - Persistence

    func saveTracks() {
        guard let data = try? JSONEncoder().encode(tracks) else { return }
        UserDefaults.standard.set(data, forKey: tracksKey)
        // 同步保存当前文件夹
        if let folder = currentFolder {
            UserDefaults.standard.set(folder.path, forKey: folderKey)
        } else {
            UserDefaults.standard.removeObject(forKey: folderKey)
        }
    }

    func loadSavedTracks() {
        guard autoRestore,
              let data = UserDefaults.standard.data(forKey: tracksKey),
              let decoded = try? JSONDecoder().decode([TrackItem].self, from: data)
        else { return }
        // 过滤掉文件已不存在的条目
        tracks = decoded.filter { FileManager.default.fileExists(atPath: $0.url.path) }
        // 恢复 currentFolder
        if let path = UserDefaults.standard.string(forKey: folderKey) {
            currentFolder = URL(fileURLWithPath: path)
            currentSortOrder = savedSortOrder(for: currentFolder)
        }
    }

    // MARK: - Track Operations

    @discardableResult
    func addFile(_ url: URL) -> Bool {
        guard isAudioFile(url), !tracks.contains(where: { $0.url == url }) else { return false }
        tracks.append(TrackItem(url: url))
        saveTracks()
        return true
    }

    func addFolder(_ url: URL) -> Int {
        var added = 0
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return 0 }
        for case let fileURL as URL in enumerator {
            if isAudioFile(fileURL) && !tracks.contains(where: { $0.url == fileURL }) {
                tracks.append(TrackItem(url: fileURL))
                added += 1
            }
        }
        if added > 0 {
            // 记录当前文件夹 + 应用记忆排序
            currentFolder = url
            let order = savedSortOrder(for: url)
            currentSortOrder = order
            applySort(order)
            saveTracks()
        }
        return added
    }

    func removeTrack(_ track: TrackItem) {
        guard let idx = tracks.firstIndex(where: { $0.id == track.id }) else { return }
        tracks.remove(at: idx)
        if let cur = currentIndex {
            if cur > idx { currentIndex = cur - 1 }
            else if cur == idx { currentIndex = tracks.isEmpty ? nil : (cur >= tracks.count ? tracks.count - 1 : cur) }
        }
        saveTracks()
    }

    func moveTrack(from source: IndexSet, to destination: Int) {
        tracks.move(fromOffsets: source, toOffset: destination)
        // 更新 currentIndex
        if let cur = currentIndex, let curID = currentTrack?.id {
            currentIndex = tracks.firstIndex(where: { $0.id == curID }) ?? cur
        }
        saveTracks()
    }

    func sort(by order: SortOrder) {
        applySort(order)
        currentSortOrder = order
        saveSortOrder(order, for: currentFolder)
        saveTracks()
    }

    /// 内部排序逻辑（不触发持久化）
    private func applySort(_ order: SortOrder) {
        let currentID = currentTrack?.id
        switch order {
        case .manual: return
        case .nameAsc:  tracks.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .nameDesc: tracks.sort { $0.title.localizedStandardCompare($1.title) == .orderedDescending }
        case .addedNewest: tracks.reverse()
        case .addedOldest: break
        }
        if let id = currentID { currentIndex = tracks.firstIndex(where: { $0.id == id }) }
    }

    func playPrevious() -> TrackItem? {
        guard let idx = currentIndex else { return tracks.first }
        currentIndex = idx > 0 ? idx - 1 : tracks.count - 1
        return currentTrack
    }

    func playNext() -> TrackItem? {
        guard let idx = currentIndex else { return tracks.first }
        currentIndex = idx + 1 < tracks.count ? idx + 1 : 0
        return currentTrack
    }

    func selectTrack(_ track: TrackItem) -> TrackItem? {
        guard let idx = tracks.firstIndex(where: { $0.id == track.id }) else { return nil }
        currentIndex = idx
        return track
    }

    func clearAll() {
        tracks.removeAll()
        currentIndex = nil
        currentFolder = nil
        saveTracks()
    }

    // MARK: - Open Panels

    func showOpenFilePanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.mp3, UTType.mpeg4Audio, UTType.wav, UTType.aiff,
                                     UTType(filenameExtension: "flac")].compactMap { $0 }
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "选择英语听力音频文件"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            _ = addFile(url)
            HistoryManager.shared.record(url: url, isFolder: false)
        }
    }

    func showOpenFolderPanel() -> Int {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "选择包含听力音频的文件夹"
        guard panel.runModal() == .OK, let url = panel.urls.first else { return 0 }
        let count = addFolder(url)
        if count > 0 { HistoryManager.shared.record(url: url, isFolder: true) }
        return count
    }

    // MARK: - Private

    private func isAudioFile(_ url: URL) -> Bool {
        Self.supportedExtensions.contains(url.pathExtension.lowercased())
    }
}

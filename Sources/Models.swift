import Foundation

/// 播放列表中的单个音频曲目
struct TrackItem: Identifiable, Codable, Equatable {
    let id: UUID
    let url: URL
    
    var title: String {
        url.deletingPathExtension().lastPathComponent
    }
    
    var fileName: String {
        url.lastPathComponent
    }
    
    init(url: URL) {
        self.id = UUID()
        self.url = url
    }
    
    static func == (lhs: TrackItem, rhs: TrackItem) -> Bool {
        lhs.id == rhs.id
    }
}

/// 播放模式
enum PlayMode: String, CaseIterable {
    case sequential = "顺序播放"
    case singleLoop = "单曲循环"
    case listLoop = "列表循环"
}

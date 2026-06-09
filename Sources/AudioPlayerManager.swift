import AVFoundation
import Combine
import SwiftUI

/// 音频播放管理器 —— 所有播放状态的中心枢纽
@MainActor
final class AudioPlayerManager: ObservableObject {
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var playbackRate: Float = 1.0
    @Published var currentTrack: TrackItem?
    @Published var playMode: PlayMode = .sequential
    @Published var isLoading = false

    // MARK: - AB 区间循环
    /// A 点（区间起点）。设置后等待 B 点。
    @Published var abLoopStart: TimeInterval?
    /// B 点（区间终点）。A、B 均设置后激活循环。
    @Published var abLoopEnd: TimeInterval?

    /// AB 循环是否已激活（A、B 都已标记）
    var isABLoopActive: Bool { abLoopStart != nil && abLoopEnd != nil }
    
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var rateObserver: NSKeyValueObservation?
    private var itemEndObserver: Any?
    
    /// 播放速度的可选档位：1.0 ~ 2.0，步长 0.1
    static let availableRates: [Float] = stride(from: 1.0, through: 2.0, by: 0.1).map { Float($0) }
    
    /// 播放下一首的回调（由 PlaylistManager 设置）
    var onTrackFinished: (() -> Void)?
    
    nonisolated init() {}
    
    // MARK: - Playback Control
    
    func loadAndPlay(track: TrackItem) {
        stop()
        
        let asset = AVURLAsset(url: track.url)
        let playerItem = AVPlayerItem(asset: asset)
        
        let newPlayer = AVPlayer(playerItem: playerItem)
        self.player = newPlayer
        self.currentTrack = track
        self.isLoading = true
        
        // 监听时长
        Task { [weak self] in
            guard let self else { return }
            do {
                let duration = try await asset.load(.duration)
                let seconds = CMTimeGetSeconds(duration)
                if seconds.isFinite && seconds > 0 {
                    await MainActor.run { self.duration = seconds }
                }
            } catch {
                await MainActor.run { self.duration = 0 }
            }
        }
        
        // 监听播放状态
        statusObserver = playerItem.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isLoading = false
                if item.status == .readyToPlay {
                    self.play(at: self.playbackRate)
                }
            }
        }
        
        // 监听实际播放速率
        rateObserver = newPlayer.observe(\.rate, options: [.new]) { [weak self] _, change in
            Task { @MainActor [weak self] in
                guard let self, let rate = change.newValue else { return }
                self.isPlaying = rate > 0
            }
        }
        
        // 时间观察器（兼顾 AB 循环检测）
        let scale = CMTimeScale(NSEC_PER_SEC)
        timeObserver = newPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: scale),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self, self.player != nil else { return }
                let t = CMTimeGetSeconds(time)
                self.currentTime = t
                // AB 循环：越过 B 点时跳回 A 点
                if let a = self.abLoopStart, let b = self.abLoopEnd, t >= b {
                    self.seek(to: a)
                    self.play()
                }
            }
        }
        
        // 曲目结束通知
        itemEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleTrackEnd()
            }
        }
    }
    
    func play(at rate: Float? = nil) {
        let targetRate = rate ?? playbackRate
        player?.play()
        player?.rate = targetRate
    }
    
    func pause() {
        player?.pause()
    }
    
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    func stop() {
        player?.pause()
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        if let observer = itemEndObserver {
            NotificationCenter.default.removeObserver(observer)
            itemEndObserver = nil
        }
        statusObserver?.invalidate()
        statusObserver = nil
        rateObserver?.invalidate()
        rateObserver = nil
        player?.replaceCurrentItem(with: nil)
        player = nil
        currentTime = 0
        duration = 0
        isPlaying = false
        isLoading = false
    }
    
    // MARK: - Seek
    
    /// 快进/快退指定秒数
    func seek(by seconds: TimeInterval) {
        guard let player else { return }
        let newTime = currentTime + seconds
        let clamped = max(0, min(newTime, duration))
        let cmTime = CMTime(seconds: clamped, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = clamped
    }
    
    /// 跳转到指定时间
    func seek(to seconds: TimeInterval) {
        guard let player else { return }
        let clamped = max(0, min(seconds, duration))
        let cmTime = CMTime(seconds: clamped, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = clamped
    }
    
    /// 快进 15 秒（seeking 后自动播放）
    func skipForward() {
        seek(by: 15)
        play()
    }
    
    /// 回退 15 秒（seeking 后自动播放）
    func skipBackward() {
        seek(by: -15)
        play()
    }
    
    // MARK: - Rate Control
    
    func increaseRate() {
        guard let idx = Self.availableRates.firstIndex(of: playbackRate),
              idx + 1 < Self.availableRates.count else { return }
        let newRate = Self.availableRates[idx + 1]
        setRate(newRate)
    }
    
    func decreaseRate() {
        guard let idx = Self.availableRates.firstIndex(of: playbackRate),
              idx > 0 else { return }
        let newRate = Self.availableRates[idx - 1]
        setRate(newRate)
    }
    
    func setRate(_ rate: Float) {
        playbackRate = rate
        if isPlaying {
            player?.rate = rate
        } else if player?.currentItem != nil {
            // 暂停中切换速度：短暂播放以应用速率再暂停
            player?.rate = rate
            player?.pause()
        }
    }
    
    /// 重置速度为 1.0x
    func resetRate() {
        setRate(1.0)
    }

    // MARK: - AB Loop

    /// 按下 A/B 按钮时调用：依次标记 A → B → 清除
    func tapABButton() {
        if abLoopStart == nil {
            abLoopStart = currentTime
        } else if abLoopEnd == nil {
            // B 点必须在 A 点之后
            if currentTime > abLoopStart! {
                abLoopEnd = currentTime
            } else {
                // 重新标记 A
                abLoopStart = currentTime
            }
        } else {
            clearABLoop()
        }
    }

    func clearABLoop() {
        abLoopStart = nil
        abLoopEnd = nil
    }
    
    // MARK: - Private
    
    private func handleTrackEnd() {
        switch playMode {
        case .singleLoop:
            seek(to: 0)
            play()
        case .sequential, .listLoop:
            onTrackFinished?()
        }
    }
    
    // MARK: - Formatting
    
    static func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "--:--" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

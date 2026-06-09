import SwiftUI
import AppKit

/// 悬浮迷你播放器视图
struct MiniPlayerView: View {
    @ObservedObject var player: AudioPlayerManager
    @ObservedObject var playlist: PlaylistManager
    let onExpand: () -> Void

    @State private var showTrackList = false

    var body: some View {
        HStack(spacing: 6) {
            playPauseButton
            Divider().frame(height: 20)
            prevButton
            nextButton
            Divider().frame(height: 20)
            skipBackButton
            skipForwardButton
            Divider().frame(height: 20)
            progressSection
            Divider().frame(height: 20)
            speedControl
            trackListButton
            expandButton
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(height: 44)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
    }

    // MARK: - Play/Pause

    private var playPauseButton: some View {
        Button(action: {
            if player.currentTrack == nil, let first = playlist.tracks.first {
                player.loadAndPlay(track: first); playlist.currentIndex = 0
            } else {
                player.togglePlayPause()
            }
        }) {
            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.accentColor)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(player.isPlaying ? "暂停" : "播放")
    }

    // MARK: - Prev / Next

    private var prevButton: some View {
        Button(action: { playPrevious() }) {
            Image(systemName: "backward.fill")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .frame(width: 24, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(playlist.tracks.count <= 1)
        .help("上一首")
    }

    private var nextButton: some View {
        Button(action: { playNext() }) {
            Image(systemName: "forward.fill")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .frame(width: 24, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(playlist.tracks.count <= 1)
        .help("下一首")
    }

    // MARK: - Skip

    private var skipBackButton: some View {
        Button(action: { player.skipBackward() }) {
            Image(systemName: "gobackward.15")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(player.currentTrack == nil)
        .help("回退 15 秒")
    }

    private var skipForwardButton: some View {
        Button(action: { player.skipForward() }) {
            Image(systemName: "goforward.15")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(player.currentTrack == nil)
        .help("快进 15 秒")
    }

    // MARK: - Progress

    private var progressSection: some View {
        VStack(spacing: 2) {
            GeometryReader { geometry in
                let progress = progressWidth(in: geometry.size.width)
                ZStack(alignment: .leading) {
                    // 阻止此区域被识别为"拖窗口"
                    NonDraggableArea()
                    // 轨道
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.25))
                        .frame(height: 4)
                    // 已播放进度
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accentColor)
                        .frame(width: progress, height: 4)
                    // 拖拽小球
                    if player.currentTrack != nil {
                        Circle()
                            .fill(Color.white)
                            .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
                            .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)
                            .frame(width: 12, height: 12)
                            .offset(x: max(0, min(geometry.size.width - 12, progress - 6)))
                            .allowsHitTesting(false)
                    }
                }
                .frame(height: 14)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    let ratio = value.location.x / geometry.size.width
                    player.seek(to: max(0, min(player.duration, ratio * player.duration)))
                })
            }
            .frame(height: 14)

            HStack {
                Text(AudioPlayerManager.formatTime(player.currentTime))
                    .font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary)
                Spacer()
                if let track = player.currentTrack {
                    Text(track.title).font(.system(size: 9)).foregroundColor(.secondary).lineLimit(1)
                }
                Spacer()
                Text(AudioPlayerManager.formatTime(player.duration))
                    .font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary)
            }
        }
    }

    private func progressWidth(in totalWidth: CGFloat) -> CGFloat {
        guard player.duration > 0 else { return 0 }
        return totalWidth * CGFloat(player.currentTime / player.duration)
    }

    // MARK: - Speed

    private var speedControl: some View {
        HStack(spacing: 3) {
            Button(action: { player.decreaseRate() }) {
                Image(systemName: "minus").font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.plain).disabled(player.playbackRate <= 1.0)
            .frame(width: 20, height: 20).contentShape(Rectangle())

            Text(String(format: "%.1fx", player.playbackRate))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(player.playbackRate == 1.0 ? .secondary : .accentColor)
                .frame(width: 36)
                .onTapGesture(count: 2) { player.resetRate() }
                .help("双击重置为 1.0x")

            Button(action: { player.increaseRate() }) {
                Image(systemName: "plus").font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.plain).disabled(player.playbackRate >= 2.0)
            .frame(width: 20, height: 20).contentShape(Rectangle())
        }
        .padding(.horizontal, 4).padding(.vertical, 2)
        .background(Color.accentColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Track List Button

    private var trackListButton: some View {
        Button(action: { showTrackListPanel() }) {
            Image(systemName: "list.bullet")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(showTrackList ? .accentColor : .secondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(playlist.tracks.isEmpty)
        .help("选择曲目")
    }

    // MARK: - Expand

    private var expandButton: some View {
        Button(action: onExpand) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).help("展开主窗口")
    }

    // MARK: - Actions

    private func playNext() {
        guard let next = playlist.playNext() else { return }
        player.loadAndPlay(track: next)
    }

    private func playPrevious() {
        if player.currentTime > 3 { player.seek(to: 0); return }
        guard let prev = playlist.playPrevious() else { return }
        player.loadAndPlay(track: prev)
    }

    /// 弹出曲目列表面板（NSPanel，显示在迷你窗口正上方）
    private func showTrackListPanel() {
        MiniTrackListPanel.show(player: player, playlist: playlist)
    }
}

// MARK: - Mini Track List Panel

/// 独立浮动面板，在迷你窗口上方或下方显示曲目列表（智能选位置 + 跟随迷你窗移动）
@MainActor
final class MiniTrackListPanel {
    private static var panel: NSPanel?
    private static var placeBelow: Bool = false
    private static var moveObserver: NSObjectProtocol?
    private static weak var miniWindowRef: NSWindow?

    static func show(player: AudioPlayerManager, playlist: PlaylistManager) {
        // 已显示则关闭（切换）
        if let existing = panel, existing.isVisible {
            close()
            return
        }

        guard let miniWindow = NSApp.windows.first(where: { $0.title == "ListenIELTS · 迷你" }),
              let screen = miniWindow.screen ?? NSScreen.main
        else { return }

        let visibleFrame = screen.visibleFrame
        let gap: CGFloat = 6
        let panelWidth = miniWindow.frame.width
        let desiredHeight = min(CGFloat(playlist.tracks.count) * 36 + 48, 320)

        // 计算上下可用空间
        let spaceAbove = visibleFrame.maxY - miniWindow.frame.maxY - gap
        let spaceBelow = miniWindow.frame.minY - visibleFrame.minY - gap

        // 优先放空间够的一侧，下方优先
        if desiredHeight <= spaceBelow {
            placeBelow = true
        } else if desiredHeight <= spaceAbove {
            placeBelow = false
        } else {
            placeBelow = spaceBelow >= spaceAbove
        }

        let availableHeight = placeBelow ? spaceBelow : spaceAbove
        let panelHeight = min(desiredHeight, max(120, availableHeight))

        let panelX = miniWindow.frame.minX
        let panelY = placeBelow
            ? miniWindow.frame.minY - panelHeight - gap
            : miniWindow.frame.maxY + gap

        let newPanel = NSPanel(
            contentRect: NSRect(x: panelX, y: panelY, width: panelWidth, height: panelHeight),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        newPanel.level = .floating
        newPanel.isMovableByWindowBackground = false
        newPanel.titlebarAppearsTransparent = true
        newPanel.titleVisibility = .hidden
        newPanel.isReleasedWhenClosed = false
        newPanel.backgroundColor = .clear

        let listView = MiniTrackListView(player: player, playlist: playlist, onClose: {
            close()
        })
        newPanel.contentView = NSHostingView(rootView: listView)
        newPanel.makeKeyAndOrderFront(nil)

        panel = newPanel
        miniWindowRef = miniWindow

        // 监听迷你窗移动 → 同步更新面板位置
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: miniWindow,
            queue: .main
        ) { _ in
            Task { @MainActor in reposition() }
        }
    }

    /// 关闭面板并清理观察者
    static func close() {
        if let observer = moveObserver {
            NotificationCenter.default.removeObserver(observer)
            moveObserver = nil
        }
        panel?.orderOut(nil)
        panel = nil
        miniWindowRef = nil
    }

    /// 跟随迷你窗移动重新定位
    private static func reposition() {
        guard let p = panel, let mini = miniWindowRef else { return }
        let gap: CGFloat = 6
        let newX = mini.frame.minX
        let newY = placeBelow
            ? mini.frame.minY - p.frame.height - gap
            : mini.frame.maxY + gap
        p.setFrameOrigin(CGPoint(x: newX, y: newY))
    }
}

/// 曲目列表视图（在浮动面板内显示）
struct MiniTrackListView: View {
    @ObservedObject var player: AudioPlayerManager
    @ObservedObject var playlist: PlaylistManager
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // 顶部：标题 + 关闭按钮
            HStack {
                Text("播放列表")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                Text("· \(playlist.tracks.count)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.6))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("关闭")
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(playlist.tracks.enumerated()), id: \.element.id) { index, track in
                        let isCurrent = player.currentTrack?.id == track.id

                        MiniTrackRow(
                            track: track,
                            isCurrent: isCurrent,
                            isPlaying: isCurrent && player.isPlaying
                        )
                        .onTapGesture {
                            _ = playlist.selectTrack(track)
                            player.loadAndPlay(track: track)
                            onClose()
                        }

                        if index < playlist.tracks.count - 1 {
                            Divider().padding(.leading, 36)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.15), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 4)
    }
}

/// 迷你窗里的单行曲目（与主窗 TrackRow 同款交互）
private struct MiniTrackRow: View {
    let track: TrackItem
    let isCurrent: Bool
    let isPlaying: Bool

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: 11))
                .foregroundColor(iconColor)
                .frame(width: 16)
            Text(track.title)
                .font(.system(size: 12))
                .foregroundColor(textColor)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isCurrent ? Color.accentColor.opacity(0.10) : (isHovered ? Color.primary.opacity(0.05) : Color.clear))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }

    private var iconName: String {
        if isPlaying { return "speaker.wave.2.fill" }
        if isCurrent { return "pause.fill" }
        return "music.note"
    }

    private var iconColor: Color {
        (isCurrent || isPlaying) ? .accentColor : .secondary.opacity(0.5)
    }

    private var textColor: Color {
        if isCurrent { return .accentColor }
        if isHovered { return .accentColor }
        return .primary
    }
}

// MARK: - NonDraggableArea
// 一个透明的 NSView，覆盖在交互控件（进度条等）下面，
// 通过 mouseDownCanMoveWindow = false 阻止 isMovableByWindowBackground
// 把这片区域识别成"拖窗口"，从而让 SwiftUI DragGesture 能正常工作。

struct NonDraggableArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = _NonDraggableNSView()
        view.wantsLayer = true
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class _NonDraggableNSView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }
}


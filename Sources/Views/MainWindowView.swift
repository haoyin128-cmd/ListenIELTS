import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct MainWindowView: View {
    @EnvironmentObject var player: AudioPlayerManager
    @EnvironmentObject var playlist: PlaylistManager
    @EnvironmentObject var history: HistoryManager

    @State private var showingClearConfirmation = false
    @State private var showSettings = false
    @State private var playlistWidth: CGFloat = 350

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                playlistPanel
                    .frame(width: playlistWidth)

                Divider()
                    .frame(width: 4)
                    .contentShape(Rectangle())
                    .background(Color.clear)
                    .onHover { hovering in
                        if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(DragGesture().onChanged { value in
                        let newWidth = playlistWidth + value.translation.width
                        playlistWidth = max(200, min(newWidth, geometry.size.width - 250))
                    })

                Divider()
                playerPanel.frame(maxWidth: .infinity)
            }
        }
        .frame(minWidth: 600, idealWidth: 750, minHeight: 420, idealHeight: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            setupTrackFinishedCallback()
            playlist.loadSavedTracks()
        }
    }

    // MARK: - Playlist Panel

    private var playlistPanel: some View {
        VStack(spacing: 0) {
            // 工具栏
            HStack(spacing: 4) {
                Text("播放列表").font(.headline)
                Spacer()

                // 历史记录
                if !history.entries.isEmpty {
                    Menu {
                        ForEach(history.entries) { entry in
                            Button(action: { loadHistory(entry) }) {
                                Label(entry.displayName,
                                      systemImage: entry.isFolder ? "folder" : "music.note")
                            }
                        }
                        Divider()
                        Button("清空历史", role: .destructive) { history.clearAll() }
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .help("最近打开")
                }

                Button(action: { playlist.showOpenFilePanel() }) {
                    Image(systemName: "doc.badge.plus")
                }
                .help("添加文件")

                Button(action: { _ = playlist.showOpenFolderPanel() }) {
                    Image(systemName: "folder.badge.plus")
                }
                .help("添加文件夹")

                if !playlist.tracks.isEmpty {
                    // 排序菜单（带当前选中标记）
                    Menu {
                        ForEach(SortOrder.allCases, id: \.self) { order in
                            Button(action: { playlist.sort(by: order) }) {
                                if playlist.currentSortOrder == order {
                                    Label(order.rawValue, systemImage: "checkmark")
                                } else {
                                    Text(order.rawValue)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .help("排序：\(playlist.currentSortOrder.rawValue)")

                    Button(role: .destructive, action: { showingClearConfirmation = true }) {
                        Image(systemName: "trash")
                    }
                    .help("清空列表")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if playlist.tracks.isEmpty {
                emptyPlaylistView
            } else {
                List {
                    ForEach(playlist.tracks) { track in
                        let isCurrent = player.currentTrack?.id == track.id
                        TrackRow(
                            track: track,
                            isPlaying: isCurrent && player.isPlaying,
                            isCurrent: isCurrent
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { playTrack(track) }
                        .contextMenu {
                            Button("播放") { playTrack(track) }
                            Divider()
                            Button("从列表中移除", role: .destructive) { playlist.removeTrack(track) }
                        }
                    }
                    .onDelete { indexSet in
                        for idx in indexSet.reversed() {
                            if playlist.tracks.indices.contains(idx) {
                                playlist.removeTrack(playlist.tracks[idx])
                            }
                        }
                    }
                    .onMove { source, destination in
                        playlist.moveTrack(from: source, to: destination)
                    }
                }
                .listStyle(.inset)
            }

            if !playlist.tracks.isEmpty {
                Divider()
                HStack {
                    Text("共 \(playlist.tracks.count) 首")
                        .font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Text("可拖拽排序").font(.caption).foregroundColor(.secondary.opacity(0.5))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }
        }
        .confirmationDialog("确定要清空播放列表吗？", isPresented: $showingClearConfirmation) {
            Button("清空", role: .destructive) {
                if player.isPlaying { player.stop() }
                playlist.clearAll()
            }
            Button("取消", role: .cancel) {}
        }
    }

    private var emptyPlaylistView: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.list")
                .font(.system(size: 48)).foregroundColor(.secondary.opacity(0.5))
            Text("播放列表为空").font(.title3).foregroundColor(.secondary)
            Text("点击按钮或拖拽文件添加").font(.caption).foregroundColor(.secondary)
            HStack(spacing: 12) {
                Button("添加文件") { playlist.showOpenFilePanel() }.buttonStyle(.borderedProminent)
                Button("添加文件夹") { _ = playlist.showOpenFolderPanel() }.buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers: providers); return true
        }
    }

    // MARK: - Player Panel

    private var playerPanel: some View {
        VStack(spacing: 12) {
            // 曲目信息
            if let track = player.currentTrack ?? playlist.currentTrack {
                VStack(spacing: 4) {
                    Text(track.title).font(.title2).fontWeight(.semibold).lineLimit(1)
                    Text(track.fileName).font(.caption).foregroundColor(.secondary).lineLimit(1)
                }
                .padding(.top, 20)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "headphones")
                        .font(.system(size: 40)).foregroundColor(.secondary.opacity(0.4))
                    Text("选择曲目开始播放").foregroundColor(.secondary)
                }
                .padding(.top, 40)
            }

            Spacer()

            // 进度条 + AB标记
            VStack(spacing: 4) {
                // AB 标记覆盖层
                if player.abLoopStart != nil || player.isABLoopActive {
                    abLoopIndicator
                }

                Slider(
                    value: Binding(get: { player.currentTime }, set: { player.seek(to: $0) }),
                    in: 0...max(player.duration, 1)
                )
                .disabled(player.currentTrack == nil)

                HStack {
                    Text(AudioPlayerManager.formatTime(player.currentTime))
                        .font(.caption).foregroundColor(.secondary).monospacedDigit()
                    Spacer()
                    // AB 循环状态文字
                    if let a = player.abLoopStart {
                        if let b = player.abLoopEnd {
                            Text("A \(AudioPlayerManager.formatTime(a)) → B \(AudioPlayerManager.formatTime(b))")
                                .font(.caption).foregroundColor(.accentColor)
                        } else {
                            Text("A \(AudioPlayerManager.formatTime(a)) → 等待B点")
                                .font(.caption).foregroundColor(.orange)
                        }
                        Spacer()
                    }
                    Text(AudioPlayerManager.formatTime(player.duration))
                        .font(.caption).foregroundColor(.secondary).monospacedDigit()
                }
            }
            .padding(.horizontal, 20)

            // 播放控制
            HStack(spacing: 24) {
                Button(action: { playPrevious() }) {
                    Image(systemName: "backward.fill").font(.title3)
                }
                .disabled(!playlist.hasPrevious && playlist.tracks.isEmpty)

                Button(action: { player.skipBackward() }) {
                    Image(systemName: "gobackward.15").font(.title3)
                }
                .disabled(player.currentTrack == nil)

                Button(action: {
                    if player.currentTrack == nil, let first = playlist.tracks.first {
                        player.loadAndPlay(track: first); playlist.currentIndex = 0
                    } else {
                        player.togglePlayPause()
                    }
                }) {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44)).foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)

                Button(action: { player.skipForward() }) {
                    Image(systemName: "goforward.15").font(.title3)
                }
                .disabled(player.currentTrack == nil)

                Button(action: { playNext() }) {
                    Image(systemName: "forward.fill").font(.title3)
                }
                .disabled(!playlist.hasNext && playlist.tracks.count <= 1)
            }

            // 速度 + 播放模式 + AB按钮
            HStack(spacing: 16) {
                // 播放速度
                HStack(spacing: 6) {
                    Button(action: { player.decreaseRate() }) {
                        Image(systemName: "minus.circle.fill").font(.title3).foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain).disabled(player.playbackRate <= 1.0)

                    Text(String(format: "%.1fx", player.playbackRate))
                        .font(.system(.body, design: .monospaced)).frame(width: 42)

                    Button(action: { player.increaseRate() }) {
                        Image(systemName: "plus.circle.fill").font(.title3).foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain).disabled(player.playbackRate >= 2.0)
                }
                .padding(.horizontal, 12).padding(.vertical, 4)
                .background(Color(nsColor: .quaternaryLabelColor).opacity(0.3))
                .clipShape(Capsule())

                // 播放模式
                Picker("模式", selection: $player.playMode) {
                    ForEach(PlayMode.allCases, id: \.self) { mode in
                        Label(mode.rawValue, systemImage: modeIcon(mode)).tag(mode)
                    }
                }
                .pickerStyle(.segmented).frame(width: 200)

                // AB 循环按钮
                abButton
            }

            // 迷你模式 + 设置
            HStack {
                Spacer()
                Button(action: {
                    NSApp.keyWindow?.orderOut(nil)
                    FloatingWindowManager.shared.show(player: player, playlist: playlist)
                }) {
                    Label("迷你悬浮窗", systemImage: "pip.enter")
                }
                .buttonStyle(.bordered).controlSize(.small)

                Button(action: { showSettings = true }) {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.bordered).controlSize(.small)
                .help("设置").padding(.trailing, 20)
            }

            Spacer()
        }
        .padding(.bottom, 12)
        .sheet(isPresented: $showSettings) { SettingsView() }
    }

    // MARK: - AB Loop UI

    private var abButton: some View {
        Button(action: { player.tapABButton() }) {
            let label: String
            let color: Color
            if player.isABLoopActive {
                label = "AB ×"; color = .accentColor
            } else if player.abLoopStart != nil {
                label = "A✓ B?"; color = .orange
            } else {
                label = "A-B"; color = .secondary
            }
            return Text(label)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(color)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(color.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .disabled(player.currentTrack == nil)
        .help(abButtonHelp)
    }

    private var abButtonHelp: String {
        if player.isABLoopActive { return "点击取消 AB 循环" }
        if player.abLoopStart != nil { return "点击标记 B 点（结束点）" }
        return "点击标记 A 点（开始点）"
    }

    private var abLoopIndicator: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                if let a = player.abLoopStart, player.duration > 0 {
                    let aX = geo.size.width * CGFloat(a / player.duration)
                    // A 点标记
                    Rectangle()
                        .fill(Color.orange)
                        .frame(width: 2, height: 8)
                        .offset(x: aX)

                    // AB 区间高亮
                    if let b = player.abLoopEnd {
                        let bX = geo.size.width * CGFloat(b / player.duration)
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.25))
                            .frame(width: max(0, bX - aX), height: 8)
                            .offset(x: aX)
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: 2, height: 8)
                            .offset(x: bX)
                    }
                }
            }
        }
        .frame(height: 8)
        .padding(.horizontal, 20)
    }

    // MARK: - Actions

    private func loadHistory(_ entry: HistoryEntry) {
        // 切换前：停止当前播放、清空列表
        if player.isPlaying || player.currentTrack != nil {
            player.stop()
        }
        playlist.clearAll()

        // 加载新内容（不自动播放）
        if entry.isFolder {
            _ = playlist.addFolder(entry.url)
        } else {
            _ = playlist.addFile(entry.url)
        }

        // 把这条记录推到历史最前面
        HistoryManager.shared.record(url: entry.url, isFolder: entry.isFolder)
    }

    private func playTrack(_ track: TrackItem) {
        _ = playlist.selectTrack(track)
        player.loadAndPlay(track: track)
    }

    private func playNext() {
        guard let next = playlist.playNext() else { return }
        player.loadAndPlay(track: next)
    }

    private func playPrevious() {
        if player.currentTime > 3 { player.seek(to: 0); return }
        guard let prev = playlist.playPrevious() else { return }
        player.loadAndPlay(track: prev)
    }

    private func modeIcon(_ mode: PlayMode) -> String {
        switch mode {
        case .sequential: return "arrow.forward"
        case .singleLoop: return "repeat.1"
        case .listLoop:   return "repeat"
        }
    }

    private func setupTrackFinishedCallback() {
        player.onTrackFinished = { [weak player, weak playlist] in
            guard let player, let playlist else { return }
            switch player.playMode {
            case .singleLoop:
                player.seek(to: 0); player.play()
            case .sequential:
                guard playlist.hasNext else { return }
                if let next = playlist.playNext() { player.loadAndPlay(track: next) }
            case .listLoop:
                if let next = playlist.playNext() { player.loadAndPlay(track: next) }
                else if let first = playlist.tracks.first { playlist.currentIndex = 0; player.loadAndPlay(track: first) }
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                Task { @MainActor in
                    if url.hasDirectoryPath {
                        let count = playlist.addFolder(url)
                        if count > 0 { HistoryManager.shared.record(url: url, isFolder: true) }
                    } else {
                        if playlist.addFile(url) { HistoryManager.shared.record(url: url, isFolder: false) }
                    }
                }
            }
        }
    }
}

// MARK: - Track Row

struct TrackRow: View {
    let track: TrackItem
    /// 是否正在播放（影响图标）
    let isPlaying: Bool
    /// 是否是当前曲目（影响文字颜色，即使暂停也保持蓝色）
    let isCurrent: Bool

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            // 图标：仅由"播放中"决定，与文字颜色解耦
            if isPlaying {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundColor(.accentColor).font(.caption)
            } else if isCurrent {
                // 当前曲目但暂停 → 暂停图标
                Image(systemName: "pause.fill")
                    .foregroundColor(.accentColor).font(.caption)
            } else {
                Image(systemName: "music.note")
                    .foregroundColor(.secondary.opacity(0.4)).font(.caption)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title).font(.body).lineLimit(1)
                    .foregroundColor(textColor)
                Text(track.fileName).font(.caption).foregroundColor(.secondary).lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onHover { hovering in isHovered = hovering }
    }

    private var textColor: Color {
        // 当前曲目 → 蓝色（无论是否在播放）
        if isCurrent { return .accentColor }
        // 鼠标悬浮 → 蓝色
        if isHovered { return .accentColor }
        return .primary
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @State private var allDesktops = FloatingWindowManager.shared.showOnAllDesktops
    @State private var autoRestore: Bool = PlaylistManager().autoRestore
    @Environment(\.dismiss) private var dismiss

    @EnvironmentObject var playlist: PlaylistManager

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("设置").font(.headline)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill").font(.title2).foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 12)

            Divider()

            VStack(spacing: 0) {
                ToggleRow(
                    icon: "rectangle.stack",
                    title: "在所有桌面显示悬浮窗",
                    description: "开启后迷你悬浮窗会在每个桌面（Space）都出现。",
                    isOn: $allDesktops
                )
                .onChange(of: allDesktops) { _, v in FloatingWindowManager.shared.showOnAllDesktops = v }

                Divider().padding(.leading, 60)

                ToggleRow(
                    icon: "arrow.counterclockwise",
                    title: "启动时恢复上次播放列表",
                    description: "下次启动应用时，自动加载上次的播放列表。",
                    isOn: $autoRestore
                )
                .onChange(of: autoRestore) { _, v in playlist.autoRestore = v }
            }
            .padding(.vertical, 8)

            Spacer()

            Text("macOS 系统限制：悬浮窗无法在其它应用的全屏 Space 中显示。\n建议使用「窗口最大化」(Option + 绿色按钮) 替代全屏。")
                .font(.caption).foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20).padding(.bottom, 16)
        }
        .frame(width: 400, height: 300)
        .onAppear { autoRestore = playlist.autoRestore }
    }
}

struct ToggleRow: View {
    let icon: String
    let title: String
    let description: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.title3).foregroundColor(.accentColor).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                Text(description).font(.caption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: $isOn).labelsHidden()
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
    }
}

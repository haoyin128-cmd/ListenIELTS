import AppKit
import SwiftUI

/// 管理悬浮迷你播放器窗口 + 偏好设置
@MainActor
final class FloatingWindowManager {
    static let shared = FloatingWindowManager()
    
    @Published var isVisible = false
    
    // MARK: - 设置（UserDefaults 持久化）

    private let defaults = UserDefaults.standard
    private let keyAllDesktops = "floating.allDesktops"

    /// 是否在所有桌面显示
    var showOnAllDesktops: Bool {
        get { defaults.object(forKey: keyAllDesktops) as? Bool ?? false }
        set {
            defaults.set(newValue, forKey: keyAllDesktops)
            applyCollectionBehavior()
        }
    }
    
    // MARK: - 窗口
    
    private var window: NSWindow?
    private weak var player: AudioPlayerManager?
    private weak var playlist: PlaylistManager?
    
    nonisolated init() {}
    
    func show(player: AudioPlayerManager, playlist: PlaylistManager) {
        self.player = player
        self.playlist = playlist

        if let existingWindow = window {
            updateContent(player: player, playlist: playlist)
            applyCollectionBehavior()
            // 每次打开都重置到默认位置（右上角）
            existingWindow.setFrameOrigin(defaultOrigin(for: existingWindow.frame.size))
            existingWindow.makeKeyAndOrderFront(nil)
            isVisible = true
            return
        }

        createWindow(player: player, playlist: playlist)
        isVisible = true
    }

    func hide() {
        window?.orderOut(nil)
        isVisible = false
    }

    /// 默认位置：屏幕右上角
    private func defaultOrigin(for size: CGSize) -> CGPoint {
        guard let screen = NSScreen.main else { return .zero }
        let f = screen.visibleFrame
        return CGPoint(x: f.maxX - size.width - 20,
                       y: f.maxY - size.height - 20)
    }
    
    // MARK: - Private
    
    private func createWindow(player: AudioPlayerManager, playlist: PlaylistManager) {
        let windowWidth: CGFloat = 520
        let windowHeight: CGFloat = 52
        let size = CGSize(width: windowWidth, height: windowHeight)

        let windowRect = NSRect(origin: defaultOrigin(for: size), size: size)

        let newWindow = NSWindow(
            contentRect: windowRect,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // 悬浮置顶
        newWindow.level = .floating
        applyCollectionBehavior(to: newWindow)
        newWindow.titlebarAppearsTransparent = true
        newWindow.titleVisibility = .hidden
        newWindow.isMovableByWindowBackground = true
        newWindow.isReleasedWhenClosed = false
        newWindow.minSize = NSSize(width: 400, height: 48)
        newWindow.maxSize = NSSize(width: 800, height: 56)
        newWindow.title = "ListenIELTS · 迷你"

        // 隐藏最小化和缩放按钮，只留关闭
        newWindow.standardWindowButton(.miniaturizeButton)?.isHidden = true
        newWindow.standardWindowButton(.zoomButton)?.isHidden = true

        // 关闭 → 隐藏并显示主窗口
        newWindow.standardWindowButton(.closeButton)?.target = self
        newWindow.standardWindowButton(.closeButton)?.action = #selector(handleClose)

        // 构建右键菜单
        newWindow.contentView?.menu = buildContextMenu()

        self.window = newWindow

        updateContent(player: player, playlist: playlist)
        newWindow.makeKeyAndOrderFront(nil)
    }
    
    private func updateContent(player: AudioPlayerManager, playlist: PlaylistManager) {
        guard let window else { return }
        
        let miniView = MiniPlayerView(
            player: player,
            playlist: playlist,
            onExpand: { [weak self] in
                self?.hide()
                NSApp.activate(ignoringOtherApps: true)
                if let mainWin = NSApp.windows.first(where: {
                    $0.title == "ListenIELTS" && $0 !== window
                }) {
                    mainWin.makeKeyAndOrderFront(nil)
                }
            }
        )
        
        let hostingView = NSHostingView(rootView: miniView)
        hostingView.autoresizingMask = [.width, .height]
        hostingView.frame = window.contentView?.bounds ?? window.frame
        
        window.contentView = hostingView
        // 重新挂载右键菜单
        window.contentView?.menu = buildContextMenu()
    }
    
    // MARK: - Collection Behavior
    
    private func applyCollectionBehavior() {
        guard let window else { return }
        applyCollectionBehavior(to: window)
    }
    
    private func applyCollectionBehavior(to window: NSWindow) {
        if showOnAllDesktops {
            window.collectionBehavior = [.canJoinAllSpaces]
        } else {
            window.collectionBehavior = []
        }
    }
    
    // MARK: - 右键菜单
    
    private func buildContextMenu() -> NSMenu {
        let menu = NSMenu()
        
        menu.addItem(NSMenuItem(
            title: "重置播放速度 → 1.0x",
            action: #selector(resetSpeed),
            keyEquivalent: ""
        ))
        
        menu.addItem(.separator())
        
        menu.addItem(NSMenuItem(
            title: "显示主窗口",
            action: #selector(showMainWindow),
            keyEquivalent: ""
        ))
        
        return menu
    }
    
    // MARK: - Actions
    
    @objc private func handleClose() {
        hide()
        NSApp.activate(ignoringOtherApps: true)
        if let mainWin = NSApp.windows.first(where: { $0.title == "ListenIELTS" && $0 !== window }) {
            mainWin.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func resetSpeed() {
        player?.setRate(1.0)
    }

    @objc private func showMainWindow() {
        hide()
        NSApp.activate(ignoringOtherApps: true)
        if let mainWin = NSApp.windows.first(where: { $0.title == "ListenIELTS" && $0 !== window }) {
            mainWin.makeKeyAndOrderFront(nil)
        }
    }
}

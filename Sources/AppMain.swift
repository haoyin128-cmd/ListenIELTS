import SwiftUI
import AppKit

/// ListenIELTS —— 雅思英语听力悬浮播放器
@main
struct ListenIELTSApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var player = AudioPlayerManager()
    @StateObject private var playlist = PlaylistManager()
    @StateObject private var history = HistoryManager.shared
    
    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environmentObject(player)
                .environmentObject(playlist)
                .environmentObject(history)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 750, height: 500)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("迷你悬浮窗") {
                    showFloatingPlayer()
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                
                Divider()
            }
            
            CommandMenu("播放") {
                Button("播放 / 暂停") {
                    togglePlayPause()
                }
                .keyboardShortcut(.space, modifiers: [])
                
                Divider()
                
                Button("回退 15 秒") {
                    player.skipBackward()
                }
                .keyboardShortcut(.leftArrow, modifiers: [])
                
                Button("快进 15 秒") {
                    player.skipForward()
                }
                .keyboardShortcut(.rightArrow, modifiers: [])
                
                Divider()
                
                Button("上一首") {
                    playPrevious()
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command])
                
                Button("下一首") {
                    playNext()
                }
                .keyboardShortcut(.rightArrow, modifiers: [.command])
                
                Divider()
                
                Menu("播放速度") {
                    ForEach(AudioPlayerManager.availableRates, id: \.self) { rate in
                        Button(String(format: "%.1fx", rate)) {
                            player.setRate(rate)
                        }
                    }
                }
                
                Divider()
                
                Menu("播放模式") {
                    ForEach(PlayMode.allCases, id: \.self) { mode in
                        Button(mode.rawValue) {
                            player.playMode = mode
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func showFloatingPlayer() {
        NSApp.keyWindow?.orderOut(nil)
        FloatingWindowManager.shared.show(player: player, playlist: playlist)
    }
    
    private func togglePlayPause() {
        if player.currentTrack == nil, let first = playlist.tracks.first {
            player.loadAndPlay(track: first)
            playlist.currentIndex = 0
        } else {
            player.togglePlayPause()
        }
    }
    
    private func playNext() {
        guard let next = playlist.playNext() else { return }
        player.loadAndPlay(track: next)
    }
    
    private func playPrevious() {
        if player.currentTime > 3 {
            player.seek(to: 0)
            return
        }
        guard let prev = playlist.playPrevious() else { return }
        player.loadAndPlay(track: prev)
    }
}

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            if let mainWindow = sender.windows.first(where: { $0.title == "ListenIELTS" }) {
                mainWindow.makeKeyAndOrderFront(nil)
            }
        }
        return true
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let window = NSApp.windows.first {
            window.title = "ListenIELTS"
            window.tabbingMode = .disallowed
        }
        HistoryManager.shared.load()
    }
}

import AppKit
import SwiftUI

@main
struct RoonLyricApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("Roon Lyric") {
            ContentView(model: model)
                .frame(minWidth: 860, minHeight: 620)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SettingsView(model: model)
                .frame(width: 620, height: 520)
        }

        MenuBarExtra("Roon Lyric", systemImage: "music.note") {
            Text(model.connection.phase.label)
            if let track = model.connection.activeZone?.nowPlaying?.trackIdentity {
                Text(track.displayTitle)
            }
            Divider()
            Button("显示桌面歌词") {
                AppLogger.info("MenuBar", "show desktop lyrics command")
                model.showLyricsWindow()
            }
            Button("隐藏桌面歌词") {
                AppLogger.info("MenuBar", "hide desktop lyrics command")
                model.hideLyricsWindow()
            }
            Button("重新扫描 Roon Core") {
                AppLogger.info("MenuBar", "rescan roon core command")
                model.discovery.sendQuery()
            }
            Divider()
            Button("设置") {
                AppLogger.info("MenuBar", "open settings command")
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            Button("退出") {
                AppLogger.info("Lifecycle", "quit command")
                NSApp.terminate(nil)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLogger.info("Lifecycle", "application did finish launching")
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppLogger.info("Lifecycle", "application will terminate")
    }
}

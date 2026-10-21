import AppKit
import SwiftUI

/// The editor is a window to make and change scenes, not a service: closing it quits it.
/// The wallpaper keeps running in the separate, light runner process.
final class EditorDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct EditorApp: App {
    @NSApplicationDelegateAdaptor(EditorDelegate.self) private var delegate
    @State private var model = AppModel()

    var body: some SwiftUI.Scene {
        WindowGroup("Splash") {
            RootView()
                .environment(model)
                .frame(minWidth: 1040, minHeight: 680)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
        Settings {
            SettingsView()
        }
    }
}

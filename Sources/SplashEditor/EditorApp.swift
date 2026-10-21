import AppKit
import SwiftUI

/// The editor is a window to make and change scenes, not a service: closing it quits it.
/// The wallpaper keeps running in the separate, light runner process.
final class EditorDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        // Looks for a newer version once a day, a short while after launch. Nothing is installed unless the user asks.
        MainActor.assumeIsolated { UpdateChecker.shared.start() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Opening the app again (from the Dock, or from the wallpaper's menu) brings the window back if it was hidden, and does nothing else.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { !flag }
}

@main
struct EditorApp: App {
    @NSApplicationDelegateAdaptor(EditorDelegate.self) private var delegate
    @State private var model = AppModel()

    var body: some SwiftUI.Scene {
        // One window only. A WindowGroup opens another window every time the app is "opened" again, which is not wanted here.
        Window("Splash", id: "main") {
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

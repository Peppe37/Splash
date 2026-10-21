import AppKit
import SplashCore

/// The real macOS wallpaper. A still scene is applied this way and nothing needs to run; a moving scene also sets a still picture
/// of itself here, so the desktop never shows an unrelated picture (in Mission Control, while Spaces slide, on a new display).
public enum DesktopImage {
    @MainActor
    public static func apply(_ url: URL) throws {
        for screen in NSScreen.screens {
            try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: options)
        }
    }

    /// Sets the picture on the current Space of every display, then, unless the user switched it off, on every other Space too.
    /// Returns what happened to the other Spaces.
    @MainActor
    @discardableResult
    public static func applyEverywhere(_ url: URL, in paths: AppPaths) async throws -> WallpaperStore.Outcome {
        let everywhere = DesktopSettings.load().applyToAllSpaces
        // The settings file is saved before the first change, so the user's own wallpapers can be put back.
        if everywhere { WallpaperStore.backUpOnce(in: paths) }
        try apply(url)
        guard everywhere else { return .unsupported }
        return await WallpaperStore.spreadToAllSpaces(imageURL: url, in: paths)
    }

    @MainActor
    private static var options: [NSWorkspace.DesktopImageOptionKey: Any] {
        [.imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue, .allowClipping: true]
    }

    // MARK: - Remembering the previous wallpaper

    struct SavedWallpaper: Codable {
        var displayID: UInt32
        var path: String
    }

    @MainActor
    private static func displayID(of screen: NSScreen) -> UInt32? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    /// Remembers the current wallpaper of every display, once. Later calls keep the first one: the original is the one to go back to.
    @MainActor
    public static func rememberCurrent(in paths: AppPaths) {
        guard !FileManager.default.fileExists(atPath: paths.previousWallpaperFile.path) else { return }
        let saved: [SavedWallpaper] = NSScreen.screens.compactMap { screen in
            guard let id = displayID(of: screen), let url = NSWorkspace.shared.desktopImageURL(for: screen),
                  url.isFileURL, !url.path.hasPrefix(paths.root.path) else { return nil }
            return SavedWallpaper(displayID: id, path: url.path)
        }
        guard !saved.isEmpty else { return }
        try? FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
        try? JSONEncoder().encode(saved).write(to: paths.previousWallpaperFile)
    }

    public static func hasRememberedWallpaper(in paths: AppPaths) -> Bool {
        FileManager.default.fileExists(atPath: paths.previousWallpaperFile.path) || WallpaperStore.hasBackup(in: paths)
    }

    /// Puts back what was remembered. A display with no saved picture gets the first one. Returns whether anything was restored.
    @MainActor
    @discardableResult
    public static func restoreRemembered(in paths: AppPaths) -> Bool {
        // The saved settings file gives every Space back its own wallpaper.
        if WallpaperStore.restoreBackup(in: paths) {
            try? FileManager.default.removeItem(at: paths.previousWallpaperFile)
            return true
        }
        guard let data = try? Data(contentsOf: paths.previousWallpaperFile),
              let saved = try? JSONDecoder().decode([SavedWallpaper].self, from: data), let first = saved.first else { return false }
        var restored = false
        for screen in NSScreen.screens {
            let entry = saved.first { $0.displayID == displayID(of: screen) } ?? first
            guard FileManager.default.fileExists(atPath: entry.path) else { continue }
            if (try? NSWorkspace.shared.setDesktopImageURL(URL(fileURLWithPath: entry.path), for: screen, options: options)) != nil { restored = true }
        }
        if restored { try? FileManager.default.removeItem(at: paths.previousWallpaperFile) }
        return restored
    }
}

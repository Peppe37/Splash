import Foundation
import SplashCore

/// macOS keeps a wallpaper for every Space of every display, in `~/Library/Application Support/com.apple.wallpaper/Store/Index.plist`.
/// The public way to set a wallpaper (`NSWorkspace.setDesktopImageURL`) only changes the Space that is on screen, so after it the other
/// Spaces, Mission Control and the slide between Spaces still show the old picture. There is no public API for "every Space".
///
/// What this does: it lets macOS write the entry for the current Space (so the format is whatever this version of macOS uses), then
/// copies that entry to every other Space and display, writes the file back and restarts the wallpaper agent so it reads it.
/// The file's format is not documented, so nothing here guesses it: if the entry macOS wrote is not found, or the layout is not what
/// is expected, nothing is changed. The original file is saved first and can be put back.
public enum WallpaperStore {
    public static var indexURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")
    }

    public static func backupURL(in paths: AppPaths) -> URL {
        paths.root.appendingPathComponent("wallpaper-store-backup.plist")
    }

    public enum Outcome: Equatable, Sendable {
        /// Every Space now shows the picture. The number is how many Spaces were set.
        case spread(spaces: Int)
        /// The store is not there or does not look like what is expected, so only the current Space was set.
        case unsupported
    }

    // MARK: - The change itself (pure, so it can be tested)

    /// Copies the entry macOS wrote for `imagePath` to every Space and display. Returns nil if that entry is not found.
    public static func spread(_ root: [String: Any], imagePath: String) -> (root: [String: Any], spaces: Int)? {
        guard var spaces = root["Spaces"] as? [String: Any] else { return nil }

        // The reference: the newest per-Space entry that points at our picture.
        var reference: (date: Date, entry: [String: Any], displays: [String: Any])?
        for case let space as [String: Any] in spaces.values {
            guard let entry = space["Default"] as? [String: Any], isPicture(entry, at: imagePath) else { continue }
            let date = (entry["Desktop"] as? [String: Any])?["LastSet"] as? Date ?? .distantPast
            if reference == nil || date > reference!.date {
                reference = (date, entry, space["Displays"] as? [String: Any] ?? [:])
            }
        }
        guard let reference else { return nil }
        let fallback = reference.displays.values.first ?? reference.entry

        func displays(_ existing: [String: Any]) -> [String: Any] {
            var result = existing
            for key in existing.keys { result[key] = reference.displays[key] ?? fallback }
            return result
        }

        var changed = 0
        for (key, value) in spaces {
            guard var space = value as? [String: Any] else { continue }
            space["Default"] = reference.entry
            if let existing = space["Displays"] as? [String: Any] { space["Displays"] = displays(existing) }
            spaces[key] = space
            changed += 1
        }

        var result = root
        result["Spaces"] = spaces
        // Displays and Spaces that appear later start from the display defaults.
        if let existing = root["Displays"] as? [String: Any] { result["Displays"] = displays(existing) }
        return (result, changed)
    }

    /// Whether an entry is a picture set by `setDesktopImageURL` for this file.
    static func isPicture(_ entry: [String: Any], at imagePath: String) -> Bool {
        guard entry["Type"] as? String == "individual",
              let desktop = entry["Desktop"] as? [String: Any],
              let content = desktop["Content"] as? [String: Any],
              let choice = (content["Choices"] as? [[String: Any]])?.first,
              choice["Provider"] as? String == "com.apple.wallpaper.choice.image",
              let data = choice["Configuration"] as? Data,
              let configuration = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              let url = configuration["url"] as? [String: Any], let relative = url["relative"] as? String,
              let path = URL(string: relative)?.path else { return false }
        return URL(fileURLWithPath: path).standardizedFileURL.path == URL(fileURLWithPath: imagePath).standardizedFileURL.path
    }

    /// How many Spaces in `root` show this picture.
    public static func spacesShowing(_ imagePath: String, in root: [String: Any]) -> (showing: Int, total: Int) {
        let spaces = (root["Spaces"] as? [String: Any])?.values.compactMap { $0 as? [String: Any] } ?? []
        return (spaces.filter { ($0["Default"] as? [String: Any]).map { isPicture($0, at: imagePath) } ?? false }.count, spaces.count)
    }

    // MARK: - Reading, writing, restarting

    static func readIndex() -> [String: Any]? {
        guard let data = try? Data(contentsOf: indexURL) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }

    /// Saves the original file, once. Later calls keep the first copy: the original is the one to go back to.
    public static func backUpOnce(in paths: AppPaths) {
        let backup = backupURL(in: paths)
        guard !FileManager.default.fileExists(atPath: backup.path), FileManager.default.fileExists(atPath: indexURL.path) else { return }
        try? FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
        try? FileManager.default.copyItem(at: indexURL, to: backup)
    }

    public static func hasBackup(in paths: AppPaths) -> Bool {
        FileManager.default.fileExists(atPath: backupURL(in: paths).path)
    }

    /// Makes the picture the wallpaper of every Space. Call it after `NSWorkspace.setDesktopImageURL`, which writes the reference entry.
    public static func spreadToAllSpaces(imageURL: URL, in paths: AppPaths) async -> Outcome {
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return .unsupported }
        backUpOnce(in: paths)

        // macOS writes the entry a moment after the call: wait for it.
        var result: (root: [String: Any], spaces: Int)?
        for _ in 0..<20 {
            if let root = readIndex(), let spread = spread(root, imagePath: imageURL.path) { result = spread; break }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        guard let result else { return .unsupported }

        guard let data = try? PropertyListSerialization.data(fromPropertyList: result.root, format: .binary, options: 0),
              (try? data.write(to: indexURL, options: .atomic)) != nil else { return .unsupported }
        restartAgent()

        // The agent may write its own state while it stops: check the file still says what we wrote, and write it again if not.
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        if let root = readIndex() {
            let state = spacesShowing(imageURL.path, in: root)
            if state.showing < state.total {
                try? data.write(to: indexURL, options: .atomic)
                restartAgent()
            }
        }
        return .spread(spaces: result.spaces)
    }

    /// Puts the saved file back, so every Space gets the wallpaper it had. Returns whether there was one to put back.
    @discardableResult
    public static func restoreBackup(in paths: AppPaths) -> Bool {
        let backup = backupURL(in: paths)
        guard let data = try? Data(contentsOf: backup),
              (try? PropertyListSerialization.propertyList(from: data, format: nil)) is [String: Any] else { return false }
        guard (try? data.write(to: indexURL, options: .atomic)) != nil else { return false }
        restartAgent()
        try? FileManager.default.removeItem(at: backup)
        return true
    }

    /// Makes the wallpaper agent read the file again. `launchctl kickstart` is refused on some Macs while System Integrity Protection
    /// is on; the agent is the user's own process and launchd starts it again at once, so ending it works everywhere.
    static func restartAgent() {
        if run("/bin/launchctl", ["kickstart", "-k", "gui/\(getuid())/com.apple.wallpaper.agent"]) != 0 {
            _ = run("/usr/bin/killall", ["WallpaperAgent"])
        }
    }

    private static func run(_ tool: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return -1 }
        process.waitUntilExit()
        return process.terminationStatus
    }
}

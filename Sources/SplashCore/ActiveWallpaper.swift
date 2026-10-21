import Foundation

/// What is on the desktop now. The editor writes it, the runner reads it.
public struct ActiveWallpaper: Codable, Equatable, Sendable {
    public var sceneDirectory: String
    public var tier: ApplyTier
    /// The baked video, for the baked tier.
    public var mediaPath: String?
    /// A picture of the scene, set as the real macOS wallpaper under the moving one. It shows in Mission Control, while Spaces slide,
    /// and on a display that has just been connected, before the runner's window is there.
    public var stillPath: String?

    public init(sceneDirectory: String, tier: ApplyTier, mediaPath: String? = nil, stillPath: String? = nil) {
        self.sceneDirectory = sceneDirectory
        self.tier = tier
        self.mediaPath = mediaPath
        self.stillPath = stillPath
    }

    public static func load(from paths: AppPaths) -> ActiveWallpaper? {
        guard let data = try? Data(contentsOf: paths.stateFile) else { return nil }
        return try? JSONDecoder().decode(ActiveWallpaper.self, from: data)
    }

    public static func save(_ wallpaper: ActiveWallpaper?, to paths: AppPaths) throws {
        try FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
        guard let wallpaper else {
            try? FileManager.default.removeItem(at: paths.stateFile)
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(wallpaper).write(to: paths.stateFile, options: .atomic)
    }
}

/// Messages between the editor and the runner. They use the system's notification center, so the runner
/// sleeps until one arrives: it never checks the state file on a timer.
public enum RunnerMessage {
    /// Read state.json again and show what it says.
    public static let reload = Notification.Name("com.giuseppe.splash.reload")
    /// The parameter values of the shown scene changed. The userInfo has a "values" JSON string.
    public static let values = Notification.Name("com.giuseppe.splash.values")
    /// The power settings changed: read them again.
    public static let settings = Notification.Name("com.giuseppe.splash.settings")
    /// Quit the runner.
    public static let quit = Notification.Name("com.giuseppe.splash.quit")

    public static func post(_ name: Notification.Name, userInfo: [String: String]? = nil) {
        DistributedNotificationCenter.default().postNotificationName(name, object: nil, userInfo: userInfo, deliverImmediately: true)
    }
}

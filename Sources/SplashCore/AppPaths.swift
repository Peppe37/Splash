import Foundation

/// Where Splash keeps its files. The root can be moved in tests.
public struct AppPaths: Sendable {
    public let root: URL

    public init(root: URL = AppPaths.defaultRoot) {
        self.root = root
    }

    /// `~/Library/Application Support/Splash`, or the folder in the SPLASH_HOME environment variable (for tests and development).
    public static var defaultRoot: URL {
        if let override = ProcessInfo.processInfo.environment["SPLASH_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Splash", isDirectory: true)
    }

    /// The user's scenes, one folder each.
    public var scenes: URL { root.appendingPathComponent("Scenes", isDirectory: true) }
    /// Videos made by the baker.
    public var baked: URL { root.appendingPathComponent("Baked", isDirectory: true) }
    /// Images made for the static tier.
    public var stills: URL { root.appendingPathComponent("Stills", isDirectory: true) }
    /// What the runner should show. Written by the editor, read by the runner.
    public var stateFile: URL { root.appendingPathComponent("state.json") }
    /// The wallpapers the user had before Splash changed them, so they can be put back.
    public var previousWallpaperFile: URL { root.appendingPathComponent("previous-wallpaper.json") }
    /// Small pictures of scenes for the library.
    public var thumbnails: URL { root.appendingPathComponent("Thumbnails", isDirectory: true) }
    /// Process id of the running runner, so only one runs at a time.
    public var runnerPIDFile: URL { root.appendingPathComponent("runner.pid") }

    public func createDirectories() throws {
        for directory in [scenes, baked, stills, thumbnails] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}

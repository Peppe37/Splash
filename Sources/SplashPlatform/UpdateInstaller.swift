import Foundation

/// The parts of installing an update that do not need a window: where a download may come from, opening the disk image,
/// and refusing anything that is not signed with the same identity as the running app. The same rules as Notcholino's updater.
///
/// Why the identity matters: macOS ties the permissions of an app (and its Keychain items) to its code signature. A release signed
/// with the project's fixed certificate keeps them across updates. An ad-hoc signature is different on every build, so an update
/// signed that way would ask for everything again. Such an update is refused here, and the user is sent to the release page.
public enum UpdateInstaller {
    public struct Failure: LocalizedError {
        public let message: String
        public var errorDescription: String? { message }
        public init(_ message: String) { self.message = message }
    }

    public static let downloadPrefix = "https://github.com/Peppe37/Splash/releases/download/"

    /// The only place a download may come from: this project's releases.
    public static func downloadURL(version: String) -> URL? {
        guard version.range(of: #"^\d+\.\d+\.\d+(-[A-Za-z0-9.]+)?$"#, options: .regularExpression) != nil,
              let url = URL(string: "\(downloadPrefix)v\(version)/Splash-\(version).dmg"),
              url.absoluteString.hasPrefix(downloadPrefix) else { return nil }
        return url
    }

    /// Whether this copy of the app can be replaced from here: it must be a real app in a folder the user can write to.
    public static func canReplace(app: URL) -> Bool {
        app.pathExtension == "app"
            && FileManager.default.isWritableFile(atPath: app.deletingLastPathComponent().path)
            && FileManager.default.isWritableFile(atPath: app.path)
    }

    /// Opens the disk image, copies the app out, and refuses anything not signed like the running app.
    public static func extract(dmg: URL, mount: URL, to staged: URL, current: URL) throws {
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        let attach = run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-noverify", "-noautoopen", "-readonly", "-mountpoint", mount.path, dmg.path])
        guard attach.status == 0 else { throw Failure("Could not open the update.") }
        defer { _ = run("/usr/bin/hdiutil", ["detach", "-force", mount.path]) }

        guard let found = try? FileManager.default.contentsOfDirectory(at: mount, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "app" }) else {
            throw Failure("The update has no app inside.")
        }
        try FileManager.default.copyItem(at: found, to: staged)
        _ = run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", staged.path])

        guard run("/usr/bin/codesign", ["--verify", "--deep", "--strict", staged.path]).status == 0 else {
            throw Failure("The update's signature is not valid, so it was not installed.")
        }
        guard identitiesMatch(running: requirement(of: current), update: requirement(of: staged)) else {
            throw Failure("The update is not signed with the same identity as this app, so macOS would ask for every permission again. Download it from the release page instead.")
        }
    }

    /// The signing requirement of an app, such as `designated => identifier "…" and certificate leaf = H"…"`.
    public static func requirement(of app: URL) -> String? {
        let output = run("/usr/bin/codesign", ["-dr", "-", app.path]).output
        return output.split(separator: "\n").first { $0.hasPrefix("designated =>") }.map(String.init)
    }

    /// Same identity: both are signed with a certificate (an ad-hoc signature has none) and have the same requirement.
    public static func identitiesMatch(running: String?, update: String?) -> Bool {
        guard let running, running.contains("certificate"), running == update else { return false }
        return true
    }

    /// A small shell script run after the app has quit: waits for it, swaps the app (putting the old one back if the copy
    /// fails), opens the new one, and, if the wallpaper runner was running before the update, starts it again.
    /// Arguments: pid, app to replace, the new app, a folder to delete, "1" if the runner has to be started again, and
    /// (optional, for tests) the tool that opens an app.
    public static let swapScript = """
        PID="$1"; DEST="$2"; NEW="$3"; WORK="$4"; RUNNER="$5"; OPEN="${6:-/usr/bin/open}"
        for i in $(seq 1 100); do kill -0 "$PID" 2>/dev/null || break; sleep 0.3; done
        kill -0 "$PID" 2>/dev/null && exit 1
        mv "$DEST" "$DEST.old" || exit 1
        if /usr/bin/ditto "$NEW" "$DEST"; then rm -rf "$DEST.old"; else rm -rf "$DEST"; mv "$DEST.old" "$DEST"; fi
        rm -rf "$WORK"
        "$OPEN" "$DEST"
        if [ "$RUNNER" = "1" ]; then "$OPEN" "$DEST/Contents/Resources/Splash Runner.app"; fi
        """

    static func run(_ tool: String, _ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return (-1, "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}

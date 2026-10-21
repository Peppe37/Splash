import SplashCore
import Darwin
import Foundation

/// Starts, finds and stops the wallpaper runner. The editor uses this to hand a scene over and then it may quit.
public struct RunnerControl: Sendable {
    public let paths: AppPaths

    public init(paths: AppPaths = AppPaths()) {
        self.paths = paths
    }

    /// The pid of the running runner, if there is one. A stale pid file (the process died, or the number was reused) does not count.
    public func runningPID() -> pid_t? {
        guard let text = try? String(contentsOf: paths.runnerPIDFile, encoding: .utf8),
              let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 0,
              kill(pid, 0) == 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        let name = (String(cString: buffer) as NSString).lastPathComponent.lowercased()
        return name.contains("splash-runner") || name.contains("splash runner") ? pid : nil
    }

    public func registerCurrentProcess() {
        try? FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
        try? "\(getpid())".write(to: paths.runnerPIDFile, atomically: true, encoding: .utf8)
    }

    public func unregisterCurrentProcess() {
        if runningPID() == getpid() { try? FileManager.default.removeItem(at: paths.runnerPIDFile) }
    }

    /// Looks for the runner next to the running program, or at the path in SPLASH_RUNNER.
    public static func runnerExecutable() -> URL? {
        sibling(named: ["splash-runner", "Splash Runner", "Splash Runner.app/Contents/MacOS/Splash Runner"], environmentKey: "SPLASH_RUNNER")
    }

    public static func cliExecutable() -> URL? {
        sibling(named: ["splash", "splash-cli"], environmentKey: "SPLASH_CLI")
    }

    public static func editorExecutable() -> URL? {
        sibling(named: ["splash-editor", "Splash"], environmentKey: "SPLASH_EDITOR")
    }

    private static func sibling(named names: [String], environmentKey: String) -> URL? {
        let fileManager = FileManager.default
        if let override = ProcessInfo.processInfo.environment[environmentKey], fileManager.isExecutableFile(atPath: override) {
            return URL(fileURLWithPath: override)
        }
        guard let own = Bundle.main.executableURL?.deletingLastPathComponent() else { return nil }
        // Next to the program (swift build), in an app bundle's Helpers or Resources, or beside the app itself.
        let folders = [own, own.appendingPathComponent("../Helpers").standardized, own.appendingPathComponent("../Resources").standardized,
                       own.appendingPathComponent("../../../").standardized]
        for folder in folders {
            for name in names {
                let candidate = folder.appendingPathComponent(name)
                if fileManager.isExecutableFile(atPath: candidate.path) { return candidate }
            }
        }
        return nil
    }

    /// Makes sure a runner is running and tells it to read the state file again.
    @discardableResult
    public func startOrReload() -> Bool {
        if runningPID() != nil {
            RunnerMessage.post(RunnerMessage.reload)
            return true
        }
        guard let executable = Self.runnerExecutable() else { return false }
        let process = Process()
        process.executableURL = executable
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            return true
        } catch {
            return false
        }
    }

    public func stop() {
        RunnerMessage.post(RunnerMessage.quit)
    }
}

import AppKit
import Foundation
import Observation
import SplashCore
import SplashPlatform

/// Tells the user when a newer version of Splash has been released.
///
/// As light as it can be: one small request to GitHub's releases list, at most once a day (and a "304 Not Modified" answer
/// when nothing changed), never while the user has switched it off. Only the editor does this, and only while it is open: the
/// wallpaper process never touches the network. It only tells the user; installing is a separate button.
@MainActor
@Observable
final class UpdateChecker {
    static let shared = UpdateChecker()

    struct Release: Equatable { let version: String; let url: URL }

    /// The newer release, if there is one.
    private(set) var available: Release?
    private(set) var isChecking = false
    private(set) var lastChecked: Date?
    private(set) var couldNotCheck = false

    private enum Key {
        static let enabled = "updateCheckEnabled"
        static let last = "updateLastCheck"
        static let etag = "updateETag"
        static let latestVersion = "updateLatestVersion"
        static let latestURL = "updateLatestURL"
    }
    private static let interval: TimeInterval = 24 * 3600
    private static let endpoint = URL(string: "https://api.github.com/repos/Peppe37/Splash/releases?per_page=30")!
    private var timer: Timer?

    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Key.enabled) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Key.enabled) }
    }

    /// The version of this build: 0.1.0, as in the app's Info.plist. A build made with `swift build` has none, and counts as older.
    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    init() {
        lastChecked = UserDefaults.standard.object(forKey: Key.last) as? Date
        applyCached()
    }

    /// Called once at launch: shows what was found last time right away, and checks if a day has passed.
    func start() {
        guard timer == nil else { return }
        // A short wait, so the check never competes with the app starting up.
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in self?.checkIfDue() }
        let timer = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkIfDue() }
        }
        timer.tolerance = 600
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func checkIfDue() {
        guard isEnabled else { return }
        if let last = lastChecked, Date().timeIntervalSince(last) < Self.interval { return }
        Task { await check() }
    }

    /// Asks GitHub now (also used by the "Check now" button).
    func check() async {
        guard !isChecking else { return }
        isChecking = true
        couldNotCheck = false
        defer { isChecking = false }

        var request = URLRequest(url: Self.endpoint, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Splash/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")
        if let etag = UserDefaults.standard.string(forKey: Key.etag) { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else {
            couldNotCheck = true   // offline or slow: try again later
            return
        }
        let defaults = UserDefaults.standard
        if http.statusCode == 200 {
            if let etag = http.value(forHTTPHeaderField: "ETag") { defaults.set(etag, forKey: Key.etag) }
            if let latest = Self.latestAppRelease(in: data) {
                defaults.set(latest.version, forKey: Key.latestVersion)
                defaults.set(latest.url.absoluteString, forKey: Key.latestURL)
            }
        } else if http.statusCode != 304 {
            couldNotCheck = true   // rate limited or a hiccup: not counted as a check
            return
        }
        let now = Date()
        defaults.set(now, forKey: Key.last)
        lastChecked = now
        applyCached()
    }

    /// The newest release of the app (tags like "v0.1.0-alpha").
    nonisolated static func latestAppRelease(in data: Data) -> Release? {
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        var best: Release?
        for entry in list where (entry["draft"] as? Bool) != true {
            guard let tag = entry["tag_name"] as? String, tag.range(of: #"^v\d+\.\d+\.\d+"#, options: .regularExpression) != nil,
                  let page = (entry["html_url"] as? String).flatMap(URL.init(string:)) else { continue }
            let version = String(tag.dropFirst())
            if best == nil || VersionOrder.isNewer(version, than: best!.version) { best = Release(version: version, url: page) }
        }
        return best
    }

    private func applyCached() {
        let defaults = UserDefaults.standard
        guard let version = defaults.string(forKey: Key.latestVersion),
              let url = defaults.string(forKey: Key.latestURL).flatMap(URL.init(string:)),
              VersionOrder.isNewer(version, than: Self.currentVersion) else {
            available = nil
            return
        }
        available = Release(version: version, url: url)
    }
}

/// Installs a new version of Splash from inside the app: downloads the release's disk image from this project's GitHub releases,
/// checks it is signed with the same identity as the running app (so macOS keeps every permission), stops the wallpaper process,
/// swaps the app, opens it again and starts the wallpaper process again if it was running. Nothing runs unless the user asks.
@MainActor
@Observable
final class AppUpdater {
    static let shared = AppUpdater()

    private(set) var status: String?
    private(set) var failure: String?
    var isWorking: Bool { status != nil }

    func install(_ release: UpdateChecker.Release) {
        guard !isWorking else { return }
        failure = nil
        status = "Downloading \(release.version)…"
        Task {
            do {
                try await run(release)
            } catch {
                status = nil
                failure = error.localizedDescription
            }
        }
    }

    private func run(_ release: UpdateChecker.Release) async throws {
        let app = Bundle.main.bundleURL
        guard UpdateInstaller.canReplace(app: app) else {
            throw UpdateInstaller.Failure("This copy of Splash can't be replaced from here (it is not an app in a folder you can write to). Download the new version instead.")
        }
        guard let url = UpdateInstaller.downloadURL(version: release.version) else {
            throw UpdateInstaller.Failure("No download for this version.")
        }

        let work = FileManager.default.temporaryDirectory.appendingPathComponent("splash-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

        let (file, response) = try await URLSession.shared.download(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateInstaller.Failure("The download failed.") }
        let dmg = work.appendingPathComponent("update.dmg")
        try FileManager.default.moveItem(at: file, to: dmg)

        status = "Checking it…"
        let staged = work.appendingPathComponent("Splash.app")
        let mount = work.appendingPathComponent("mount")
        try await Task.detached(priority: .utility) {
            try UpdateInstaller.extract(dmg: dmg, mount: mount, to: staged, current: app)
        }.value

        status = "Restarting…"
        // The wallpaper process runs from inside the app that is about to be replaced: stop it, and start it again afterwards.
        let paths = AppPaths()
        let runner = RunnerControl(paths: paths)
        let runnerWasRunning = runner.runningPID() != nil
        if runnerWasRunning { runner.stop() }

        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = ["-c", UpdateInstaller.swapScript, "sh", String(ProcessInfo.processInfo.processIdentifier),
                            app.path, staged.path, work.path, runnerWasRunning ? "1" : "0"]
        try helper.run()
        NSApp.terminate(nil)
    }
}

import AppKit
import SplashCore
import SplashPlatform
import Observation
import SwiftUI

/// `Scene` alone would clash with SwiftUI's `Scene`.
typealias WallpaperScene = SplashCore.Scene

/// Gives the model a way to reach the preview's web view (to take a picture of it, or to send it new parameters).
@MainActor
final class PreviewHandle {
    weak var webView: SceneWebView?
}

struct Banner: Equatable {
    var text: String
    var isError: Bool
}

enum ApplyState: Equatable {
    case idle
    case working(String, progress: Double?)
}

/// The state of the editor window: the library, the selected scene, its parameter values, and what is applied.
@MainActor
@Observable
final class AppModel {
    let paths: AppPaths
    let library: SceneLibrary
    let runner: RunnerControl
    let preview = PreviewHandle()
    let annotations = AnnotationModel()
    let thumbnails: ThumbnailStore
    /// The way the next Apply will put the scene on the desktop.
    var chosenTier: ApplyTier = .live

    var scenes: [WallpaperScene] = []
    private(set) var selectedID: String?
    var values: [String: JSONValue] = [:]
    var issues: [LintIssue] = []
    var history: [HistoryEntry] = []
    /// Changes when the preview must load the scene again.
    var previewToken = 0
    var banner: Banner?
    var applyState: ApplyState = .idle
    var applied: ActiveWallpaper?
    var chats: [String: ChatModel] = [:]

    private var saveTask: Task<Void, Never>?
    private var applyTask: Task<Void, Never>?
    private var lastLiveReload = Date.distantPast

    init(paths: AppPaths = AppPaths()) {
        self.paths = paths
        self.library = SceneLibrary(paths: paths)
        self.runner = RunnerControl(paths: paths)
        self.thumbnails = ThumbnailStore(paths: paths)
        try? paths.createDirectories()
        thumbnails.syncPresets(Presets.all)
        refresh()
        // For development and screenshots: open on a given scene.
        if let id = ProcessInfo.processInfo.environment["SPLASH_SELECT"], scenes.contains(where: { $0.manifest.id == id }) { select(id) }
        applied = ActiveWallpaper.load(from: paths)
        if runner.runningPID() == nil, applied?.tier == .live || applied?.tier == .baked { applied = nil }
    }

    var selected: WallpaperScene? {
        scenes.first { $0.manifest.id == selectedID }
    }

    func chat(for scene: WallpaperScene) -> ChatModel {
        if let existing = chats[scene.manifest.id] { return existing }
        let created = ChatModel(app: self, sceneID: scene.manifest.id)
        chats[scene.manifest.id] = created
        return created
    }

    // MARK: - Library

    func refresh() {
        scenes = library.scenes()
        thumbnails.sync(scenes)
        if let selectedID, !scenes.contains(where: { $0.manifest.id == selectedID }) { select(nil) }
    }

    func select(_ id: String?) {
        guard id != selectedID else { return }
        selectedID = id
        annotations.reset()
        loadSelection()
    }

    private func loadSelection() {
        guard let scene = selected else {
            values = [:]; issues = []; history = []
            return
        }
        values = ParamStore.load(for: scene)
        issues = SceneLinter.lint(scene)
        history = SceneHistory(scene: scene).entries()
        chosenTier = applied?.sceneDirectory == scene.directory.path ? (applied?.tier ?? scene.manifest.preferredTier) : scene.manifest.preferredTier
        previewToken += 1
    }

    func create(from preset: Preset) {
        run("Could not create the scene") {
            let scene = try self.library.create(from: preset)
            self.refresh()
            self.select(scene.manifest.id)
        }
    }

    func duplicateSelected() {
        guard let scene = selected else { return }
        run("Could not duplicate the scene") {
            let copy = try self.library.duplicate(scene, name: scene.manifest.name + " copy")
            self.refresh()
            self.select(copy.manifest.id)
        }
    }

    func rename(_ scene: WallpaperScene, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != scene.manifest.name else { return }
        run("Could not rename the scene") {
            _ = try self.library.rename(scene, to: trimmed)
            self.refresh()
        }
    }

    func delete(_ scene: WallpaperScene) {
        run("Could not delete the scene") {
            if self.applied?.sceneDirectory == scene.directory.path { self.stopWallpaper() }
            try self.library.delete(scene)
            self.chats[scene.manifest.id] = nil
            self.refresh()
        }
    }

    func revealSelected() {
        guard let scene = selected else { return }
        NSWorkspace.shared.activateFileViewerSelecting([scene.directory])
    }

    // MARK: - Parameters

    func setValue(_ key: String, to value: JSONValue) {
        guard let scene = selected else { return }
        values[key] = value
        let json = ParamStore.json(values)
        preview.webView?.setParams(json: json)
        // A live wallpaper follows the sliders as you move them.
        if applied?.tier == .live, applied?.sceneDirectory == scene.directory.path {
            RunnerMessage.post(RunnerMessage.values, userInfo: ["values": json])
        }
        saveTask?.cancel()
        let snapshot = values
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            try? ParamStore.save(snapshot, for: scene)
            self?.thumbnails.sync([scene])
            self?.saveTask = nil
        }
    }

    func resetValues() {
        guard let scene = selected else { return }
        for param in scene.manifest.params { setValue(param.key, to: param.default) }
    }

    // MARK: - Preview, lint, history

    func reloadPreview() {
        previewToken += 1
    }

    /// Reads the scene folder again. An agent may have changed scene.json as well as the code.
    func reloadSelectedFromDisk() {
        guard let id = selectedID else { return }
        refresh()
        if let scene = scenes.first(where: { $0.manifest.id == id }) {
            values = ParamStore.load(for: scene)
            issues = SceneLinter.lint(scene)
            history = SceneHistory(scene: scene).entries()
        }
        previewToken += 1
    }

    /// Reloads the preview while an agent works, at most once a second.
    func reloadWhileAgentWorks() {
        guard Date().timeIntervalSince(lastLiveReload) > 1 else { return }
        lastLiveReload = Date()
        reloadSelectedFromDisk()
    }

    func takeSnapshot(label: String) {
        guard let scene = selected else { return }
        run("Could not save a version") {
            try SceneHistory(scene: scene).snapshot(label: label)
            self.history = SceneHistory(scene: scene).entries()
        }
    }

    func restore(_ entry: HistoryEntry) {
        guard let scene = selected else { return }
        run("Could not restore that version") {
            try SceneHistory(scene: scene).restore(entry)
            self.reloadSelectedFromDisk()
            self.banner = Banner(text: "Restored \"\(entry.label)\". The version before it is saved too.", isError: false)
        }
    }

    // MARK: - Apply

    func canApply(_ tier: ApplyTier) -> Bool {
        selected?.manifest.tiers.contains(tier) ?? false
    }

    func apply(_ tier: ApplyTier) {
        guard let scene = selected, applyState == .idle else { return }
        guard scene.manifest.tiers.contains(tier) else {
            banner = Banner(text: "This scene does not support that way of applying.", isError: true)
            return
        }
        let errors = issues.filter { $0.severity == .error }
        guard errors.isEmpty else {
            banner = Banner(text: "Fix the scene first: \(errors[0].message)", isError: true)
            return
        }
        let values = self.values
        try? ParamStore.save(values, for: scene)
        DesktopImage.rememberCurrent(in: paths)

        applyTask = Task { [weak self] in
            guard let self else { return }
            defer { self.applyState = .idle; self.applyTask = nil }
            do {
                switch tier {
                case .live:
                    self.applyState = .working("Preparing…", progress: nil)
                    let still = try await self.makeStill(of: scene, values: values)
                    try self.hand(over: ActiveWallpaper(sceneDirectory: scene.directory.path, tier: .live, stillPath: still.path))
                    self.banner = Banner(text: "\(scene.manifest.name) is running live. You can close Splash.", isError: false)
                case .baked:
                    self.applyState = .working("Recording one loop…", progress: 0)
                    let output = self.paths.baked.appendingPathComponent("\(scene.manifest.id).mov")
                    var options = BakeOptions.forMainScreen(fps: min(scene.manifest.fps, 30))
                    options.fps = max(options.fps, 10)
                    try await Baker.bake(scene: scene, values: values, options: options, to: output) { fraction in
                        self.applyState = .working("Recording one loop…", progress: fraction)
                    }
                    let still = try await self.makeStill(of: scene, values: values)
                    try self.hand(over: ActiveWallpaper(sceneDirectory: scene.directory.path, tier: .baked, mediaPath: output.path, stillPath: still.path))
                    self.banner = Banner(text: "\(scene.manifest.name) is playing as a video loop. You can close Splash.", isError: false)
                case .static:
                    self.applyState = .working("Drawing the picture…", progress: nil)
                    let options = BakeOptions.forMainScreen()
                    _ = options
                    let file = try await self.makeStill(of: scene, values: values)
                    try self.hand(over: ActiveWallpaper(sceneDirectory: scene.directory.path, tier: .static, stillPath: file.path))
                    self.banner = Banner(text: "\(scene.manifest.name) is now your wallpaper. Nothing keeps running.", isError: false)
                }
            } catch is CancellationError {
                self.banner = Banner(text: "Stopped.", isError: false)
            } catch {
                self.banner = Banner(text: "Could not apply: \(error)", isError: true)
            }
        }
    }

    func cancelApply() {
        applyTask?.cancel()
    }

    /// Draws one picture of the scene at full quality, saves it, and sets it as the real macOS wallpaper on every display.
    /// For a still scene this is the whole job. For a moving one it is the picture under the motion.
    private func makeStill(of scene: WallpaperScene, values: [String: JSONValue]) async throws -> URL {
        let options = BakeOptions.forMainScreen()
        let renderer = OffscreenRenderer(scene: scene, values: values, size: CGSize(width: options.width, height: options.height))
        defer { renderer.close() }
        try await renderer.load()
        let image = try await renderer.image(at: scene.manifest.stillTime)
        try FileManager.default.createDirectory(at: paths.stills, withIntermediateDirectories: true)
        // A new file name each time, or macOS may keep showing the old picture.
        let file = paths.stills.appendingPathComponent("\(scene.manifest.id)-\(Int(Date().timeIntervalSince1970)).png")
        try OffscreenRenderer.writePNG(image, to: file)
        try DesktopImage.apply(file)
        // Older pictures of this scene are not needed any more.
        for old in (try? FileManager.default.contentsOfDirectory(at: paths.stills, includingPropertiesForKeys: nil)) ?? []
        where old != file && old.lastPathComponent.hasPrefix(scene.manifest.id + "-") {
            try? FileManager.default.removeItem(at: old)
        }
        return file
    }

    /// Writes the state file and wakes the runner, which reads it. For a static wallpaper the runner quits: the picture is the real wallpaper.
    private func hand(over wallpaper: ActiveWallpaper) throws {
        try ActiveWallpaper.save(wallpaper, to: paths)
        applied = wallpaper
        switch wallpaper.tier {
        case .static:
            if runner.runningPID() != nil { RunnerMessage.post(RunnerMessage.reload) }
        case .baked, .live:
            guard runner.startOrReload() else {
                throw RunnerError.notFound
            }
        }
    }

    /// Stops the runner and puts the user's previous wallpaper back, if it was remembered.
    func stopWallpaper() {
        try? ActiveWallpaper.save(nil, to: paths)
        applied = nil
        runner.stop()
        if DesktopImage.restoreRemembered(in: paths) {
            banner = Banner(text: "Stopped. Your previous wallpaper is back.", isError: false)
        } else {
            banner = Banner(text: "Stopped. The last picture stays as your wallpaper.", isError: false)
        }
    }

    var canRestoreWallpaper: Bool { DesktopImage.hasRememberedWallpaper(in: paths) }

    /// For a still wallpaper, which needs no runner: puts the previous wallpaper back.
    func restorePreviousWallpaper() {
        if applied != nil { stopWallpaper(); return }
        if DesktopImage.restoreRemembered(in: paths) {
            banner = Banner(text: "Your previous wallpaper is back.", isError: false)
        } else {
            banner = Banner(text: "There is no previous wallpaper to put back.", isError: true)
        }
    }

    var isAppliedSceneSelected: Bool {
        guard let applied, let selected else { return false }
        return applied.sceneDirectory == selected.directory.path
    }

    // MARK: - Helpers

    private func run(_ failure: String, _ work: () throws -> Void) {
        do { try work() } catch { banner = Banner(text: "\(failure): \(error.localizedDescription)", isError: true) }
    }
}

enum RunnerError: Error, LocalizedError {
    case notFound

    var errorDescription: String? {
        "The wallpaper runner (splash-runner) was not found next to Splash. Build it with `swift build`, or set SPLASH_RUNNER to its path."
    }
}

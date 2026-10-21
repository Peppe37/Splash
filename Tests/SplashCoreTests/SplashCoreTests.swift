import Foundation
import Testing
@testable import SplashCore

@Suite("PerformancePolicy")
struct PerformancePolicyTests {
    @Test func runsAtSceneFPSOnPower() {
        #expect(PerformancePolicy.decide(sceneFPS: 30, state: SystemState()) == .run(fps: 30))
    }

    @Test func capsSceneFPSToSixty() {
        #expect(PerformancePolicy.decide(sceneFPS: 120, state: SystemState()) == .run(fps: 60))
    }

    @Test func batteryLowersFPS() {
        let state = SystemState(onBattery: true)
        #expect(PerformancePolicy.decide(sceneFPS: 30, state: state) == .run(fps: 15))
    }

    @Test func batteryCanPause() {
        let state = SystemState(onBattery: true)
        let settings = PowerSettings(pauseOnBattery: true)
        #expect(PerformancePolicy.decide(sceneFPS: 30, state: state, settings: settings) == .pause)
    }

    @Test func lowPowerModePausesByDefault() {
        #expect(PerformancePolicy.decide(sceneFPS: 30, state: SystemState(lowPowerMode: true)) == .pause)
    }

    @Test func occlusionAndSleepFreeTheRenderer() {
        #expect(PerformancePolicy.decide(sceneFPS: 30, state: SystemState(occluded: true)) == .suspend)
        #expect(PerformancePolicy.decide(sceneFPS: 30, state: SystemState(screenAsleep: true)) == .suspend)
        #expect(PerformancePolicy.decide(sceneFPS: 30, state: SystemState(screenLocked: true)) == .suspend)
    }

    @Test func userPauseWins() {
        #expect(PerformancePolicy.decide(sceneFPS: 30, state: SystemState(userPaused: true)) == .pause)
    }

    @Test func thermalPressureSlowsThenPauses() {
        #expect(PerformancePolicy.decide(sceneFPS: 30, state: SystemState(thermal: .fair)) == .run(fps: 24))
        #expect(PerformancePolicy.decide(sceneFPS: 30, state: SystemState(thermal: .serious)) == .pause)
    }
}

@Suite("SceneLinter")
struct SceneLinterTests {
    /// Writes a scene to a temporary folder, runs the linter, and removes the folder.
    private func lint(_ manifest: SceneManifest, html: String = "<html></html>") throws -> [String] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("splash-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try Scene.write(manifest, to: directory)
        try html.write(to: directory.appendingPathComponent(manifest.entry), atomically: true, encoding: .utf8)
        return SceneLinter.lint(try Scene.load(from: directory)).map(\.code)
    }

    @Test func templateIsClean() throws {
        let manifest = SceneTemplates.manifest(id: "gradient-drift", name: "Gradient drift")
        #expect(try lint(manifest, html: SceneTemplates.indexHTML) == [])
    }

    @Test func badIdAndMissingEntry() {
        var manifest = SceneTemplates.manifest(id: "Bad Id", name: "x")
        manifest.entry = "missing.html"
        let codes = SceneLinter.lint(Scene(directory: FileManager.default.temporaryDirectory, manifest: manifest)).map(\.code)
        #expect(codes.contains("id"))
        #expect(codes.contains("entry"))
    }

    @Test func bakedNeedsLoopSeconds() throws {
        var manifest = SceneTemplates.manifest(id: "a", name: "a")
        manifest.loopSeconds = nil
        #expect(try lint(manifest).contains("loop-seconds"))
    }

    @Test func audioMustBeLiveOnly() throws {
        var manifest = SceneTemplates.manifest(id: "a", name: "a")
        manifest.permissions.audio = true
        #expect(try lint(manifest).contains("audio-tier"))
    }

    @Test func remoteURLNeedsNetworkPermission() throws {
        let manifest = SceneTemplates.manifest(id: "a", name: "a")
        #expect(try lint(manifest, html: "<script src=\"https://cdn.example.com/x.js\"></script>").contains("network"))
    }

    @Test func remoteURLAllowedWithNetworkPermission() throws {
        var manifest = SceneTemplates.manifest(id: "a", name: "a")
        manifest.permissions.network = true
        #expect(try lint(manifest, html: "<script src=\"https://cdn.example.com/x.js\"></script>").contains("network") == false)
    }

    @Test func paramDefaultOutsideRange() throws {
        var manifest = SceneTemplates.manifest(id: "a", name: "a")
        manifest.params = [SceneParam(key: "speed", label: "Speed", type: .number, default: .number(9), min: 0, max: 3)]
        #expect(try lint(manifest).contains("param-range"))
    }

    @Test func duplicateParamKey() throws {
        var manifest = SceneTemplates.manifest(id: "a", name: "a")
        manifest.params = [
            SceneParam(key: "k", label: "K", type: .bool, default: .bool(true)),
            SceneParam(key: "k", label: "K2", type: .bool, default: .bool(false)),
        ]
        #expect(try lint(manifest).contains("param-duplicate"))
    }
}

@Suite("SceneManifest")
struct ManifestTests {
    @Test func decodesMinimalManifestWithDefaults() throws {
        let json = Data(#"{"id":"a","name":"A"}"#.utf8)
        let manifest = try JSONDecoder().decode(SceneManifest.self, from: json)
        #expect(manifest.entry == "index.html")
        #expect(manifest.fps == 30)
        #expect(manifest.tiers == [.baked, .live])
        #expect(manifest.permissions.network == false)
    }

    @Test func roundTrip() throws {
        let manifest = SceneTemplates.manifest(id: "gradient-drift", name: "Gradient drift")
        let data = try JSONEncoder().encode(manifest)
        #expect(try JSONDecoder().decode(SceneManifest.self, from: data) == manifest)
    }

    @Test func defaultParamsJSON() {
        let json = SceneRuntimeScript.defaultParamsJSON(for: SceneTemplates.manifest(id: "a", name: "a"))
        #expect(json.contains("\"speed\":1"))
        #expect(json.contains("#5b3df5"))
    }
}

@Suite("Presets")
struct PresetTests {
    @Test func everyPresetLintsClean() throws {
        for preset in Presets.all {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("splash-preset-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: directory) }
            let scene = try preset.install(at: directory)
            let issues = SceneLinter.lint(scene)
            #expect(issues == [], "preset \(preset.id): \(issues)")
        }
    }

    @Test func idsAreUnique() {
        #expect(Set(Presets.all.map(\.id)).count == Presets.all.count)
    }

    @Test func installWritesAgentFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("splash-preset-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try Presets.all[0].install(at: directory)
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("AGENTS.md").path))
        #expect(try String(contentsOf: directory.appendingPathComponent("CLAUDE.md"), encoding: .utf8).contains("@AGENTS.md"))
    }
}

private func makePaths() -> AppPaths {
    AppPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent("splash-lib-\(UUID().uuidString)"))
}

@Suite("SceneLibrary")
struct SceneLibraryTests {
    @Test func createListDuplicateDelete() throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let library = SceneLibrary(paths: paths)

        let first = try library.create(from: Presets.find("waves")!)
        let second = try library.create(from: Presets.find("waves")!)
        #expect(first.manifest.id == "waves")
        #expect(second.manifest.id == "waves-2")
        #expect(library.scenes().count == 2)

        let copy = try library.duplicate(first, name: "Calm sea")
        #expect(copy.manifest.id == "calm-sea")
        #expect(copy.manifest.name == "Calm sea")
        #expect(library.scenes().map(\.manifest.name).contains("Calm sea"))

        try library.delete(copy)
        #expect(library.scenes().count == 2)
    }

    @Test func deleteRefusesFoldersOutsideTheLibrary() throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("splash-outside-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: outside) }
        let scene = try Presets.all[0].install(at: outside)
        try SceneLibrary(paths: paths).delete(scene)
        #expect(FileManager.default.fileExists(atPath: outside.path))
    }

    @Test func slug() {
        #expect(SceneLibrary.slug("Calm Sea!") == "calm-sea")
        #expect(SceneLibrary.slug("Città  nuova") == "citta-nuova")
        #expect(SceneLibrary.slug("***") == "scene")
    }
}

@Suite("ParamStore")
struct ParamStoreTests {
    @Test func defaultsThenSavedValues() throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let scene = try SceneLibrary(paths: paths).create(from: Presets.find("aurora")!)

        #expect(ParamStore.load(for: scene)["speed"] == .number(1))
        var values = ParamStore.load(for: scene)
        values["speed"] = .number(3)
        values["colorA"] = .string("#112233")
        try ParamStore.save(values, for: scene)
        #expect(ParamStore.load(for: scene)["speed"] == .number(3))
        #expect(ParamStore.load(for: scene)["colorA"] == .string("#112233"))
    }

    @Test func invalidSavedValuesFallBackToDefaults() throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let scene = try SceneLibrary(paths: paths).create(from: Presets.find("aurora")!)
        try ParamStore.save(["speed": .number(99), "colorA": .string("red")], for: scene)
        #expect(ParamStore.load(for: scene)["speed"] == .number(1))
        #expect(ParamStore.load(for: scene)["colorA"] == .string("#27e1a0"))
    }
}

@Suite("SceneHistory")
struct SceneHistoryTests {
    @Test func snapshotAndRestore() throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let scene = try SceneLibrary(paths: paths).create(from: Presets.find("waves")!)
        let history = SceneHistory(scene: scene)
        let index = scene.directory.appendingPathComponent("index.html")
        let original = try String(contentsOf: index, encoding: .utf8)

        let entry = try history.snapshot(label: "Start", date: Date(timeIntervalSince1970: 1_000))
        try "changed".write(to: index, atomically: true, encoding: .utf8)
        try history.restore(entry)

        #expect(try String(contentsOf: index, encoding: .utf8) == original)
        // The restore saved the changed state first, so it can be undone.
        #expect(history.entries().count == 2)
        #expect(history.entries().contains { $0.label.hasPrefix("Before restoring") })
    }

    @Test func historyDoesNotCopyItself() throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let scene = try SceneLibrary(paths: paths).create(from: Presets.find("waves")!)
        let history = SceneHistory(scene: scene)
        try history.snapshot(label: "One", date: Date(timeIntervalSince1970: 1_000))
        let second = try history.snapshot(label: "Two", date: Date(timeIntervalSince1970: 2_000))
        let copied = try FileManager.default.contentsOfDirectory(atPath: scene.directory.appendingPathComponent(".splash/history/\(second.id)/files").path)
        #expect(!copied.contains(".splash"))
    }

    @Test func prunesOldEntries() throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let scene = try SceneLibrary(paths: paths).create(from: Presets.find("blank")!)
        let history = SceneHistory(scene: scene)
        for index in 0..<(SceneHistory.keepLimit + 5) {
            try history.snapshot(label: "n\(index)", date: Date(timeIntervalSince1970: Double(1_000 + index)))
        }
        #expect(history.entries().count == SceneHistory.keepLimit)
    }
}

@Suite("Agents")
struct AgentTests {
    @Test func promptMentionsImageAndComments() {
        let request = AgentRequest(
            text: "Make the sky warmer",
            annotatedImage: URL(fileURLWithPath: "/scene/.splash/annotations/a.png"),
            comments: [Comment(x: 0.25, y: 0.5, time: 3, text: "too blue here")],
            splashCLI: "/usr/local/bin/splash")
        let prompt = request.prompt(sceneDirectory: URL(fileURLWithPath: "/scene"))
        #expect(prompt.contains("Make the sky warmer"))
        #expect(prompt.contains(".splash/annotations/a.png"))
        #expect(prompt.contains("1. at (0.25, 0.50), at 3.00 s: too blue here"))
        #expect(prompt.contains("/usr/local/bin/splash lint ."))
    }

    @Test func claudeArgumentsAreNonInteractive() {
        let arguments = AgentKind.claude.arguments(prompt: "hi", imagePath: nil, splashCLI: "/x/splash")
        #expect(arguments.first == "-p")
        #expect(arguments.contains("acceptEdits"))
        #expect(arguments.last?.contains("Bash(/x/splash:*)") == true)
    }

    @Test func parsesClaudeStream() {
        let text = #"{"type":"assistant","message":{"content":[{"type":"text","text":"Done."}]}}"#
        #expect(AgentOutputParser.parse(line: text, kind: .claude) == [.text("Done.")])
        let tool = #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/a/b/index.html"}}]}}"#
        #expect(AgentOutputParser.parse(line: tool, kind: .claude) == [.activity("Edit index.html")])
        #expect(AgentOutputParser.parse(line: #"{"type":"result","is_error":false}"#, kind: .claude) == [.finished(success: true)])
        #expect(AgentOutputParser.parse(line: #"{"type":"system","subtype":"init"}"#, kind: .claude) == [])
    }

    @Test func openCodeIsOffByDefault() {
        #expect(AgentKind.claude.isEnabled)
        #expect(AgentKind.codex.isEnabled)
        #expect(AgentKind.opencode.isEnabled == (ProcessInfo.processInfo.environment["SPLASH_ENABLE_OPENCODE"] == "1"))
    }

    @Test func promptKeepsAgentInsideTheFolder() {
        let prompt = AgentRequest(text: "x").prompt(sceneDirectory: URL(fileURLWithPath: "/scene"))
        #expect(prompt.contains("Only read and change files inside the current working directory"))
    }

    @Test func plainAgentsPassTextThrough() {
        #expect(AgentOutputParser.parse(line: "  changed the sky ", kind: .opencode) == [.text("changed the sky")])
        #expect(AgentOutputParser.parse(line: "   ", kind: .codex) == [])
    }
}

@Suite("ActiveWallpaper")
struct ActiveWallpaperTests {
    @Test func saveLoadClear() throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        #expect(ActiveWallpaper.load(from: paths) == nil)
        let value = ActiveWallpaper(sceneDirectory: "/s", tier: .baked, mediaPath: "/s.mp4")
        try ActiveWallpaper.save(value, to: paths)
        #expect(ActiveWallpaper.load(from: paths) == value)
        try ActiveWallpaper.save(nil, to: paths)
        #expect(ActiveWallpaper.load(from: paths) == nil)
    }
}

@Suite("Fingerprint and still")
struct FingerprintTests {
    @Test func changesWhenFilesOrValuesChange() throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let scene = try SceneLibrary(paths: paths).create(from: Presets.find("waves")!)
        let before = scene.fingerprint()
        #expect(before == scene.fingerprint())
        try "<html>changed</html>".write(to: scene.directory.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        let afterFile = scene.fingerprint()
        #expect(afterFile != before)
        try ParamStore.save(["speed": .number(2)], for: scene)
        #expect(scene.fingerprint() != afterFile)
    }

    @Test func historyDoesNotChangeTheFingerprint() throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let scene = try SceneLibrary(paths: paths).create(from: Presets.find("waves")!)
        let before = scene.fingerprint()
        try SceneHistory(scene: scene).snapshot(label: "x")
        #expect(scene.fingerprint() == before)
    }

    @Test func stillTimeIsAQuarterOfTheLoop() {
        #expect(Presets.find("aurora")!.manifest.stillTime == 6)
        #expect(Presets.find("dusk")!.manifest.stillTime == 0)
    }

    @Test func activeWallpaperKeepsTheStillPicture() throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let value = ActiveWallpaper(sceneDirectory: "/s", tier: .baked, mediaPath: "/s.mov", stillPath: "/s.png")
        try ActiveWallpaper.save(value, to: paths)
        #expect(ActiveWallpaper.load(from: paths)?.stillPath == "/s.png")
    }

    @Test func presetsReadTheResolutionFromTheHost() {
        for preset in Presets.all where preset.id != "blank" {
            let html = preset.files["index.html"] ?? ""
            #expect(html.contains("splash.detail"), "preset \(preset.id)")
        }
    }
}

@Suite("VersionOrder")
struct VersionOrderTests {
    @Test func comparesNumbersNotText() {
        #expect(VersionOrder.isNewer("0.2.0-alpha", than: "0.1.9-alpha"))
        #expect(VersionOrder.isNewer("0.10.0-alpha", than: "0.9.0-alpha"))
        #expect(!VersionOrder.isNewer("0.1.0-alpha", than: "0.1.0-alpha"))
        #expect(!VersionOrder.isNewer("0.1.0-alpha", than: "0.1.1-alpha"))
        #expect(VersionOrder.isNewer("1.0.0", than: "0.28.2-alpha"))
    }

    @Test func aDevelopmentBuildIsOlderThanAnyRelease() {
        #expect(VersionOrder.isNewer("0.1.0-alpha", than: "dev"))
        #expect(!VersionOrder.isNewer("nonsense", than: "0.1.0-alpha"))
    }
}

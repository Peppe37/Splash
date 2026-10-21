import AppKit
import SplashCore
import SplashPlatform
import Foundation

// `splash`: the command line tool. Non-interactive on purpose, so AI agents can drive it.

let version = "0.1.0"

let usage = """
splash \(version): animated and procedural wallpapers for macOS

Usage:
  splash init <id> [--name "Display name"] [--preset <id>]   Create a scene folder from a preset (default: gradient-drift)
  splash presets [export <folder>]           List the built-in presets, or write them all into a folder
  splash lint <scene-folder>                 Check a scene; exit code 1 if there are errors
  splash snapshot <scene-folder> <out.png> [--time <seconds>] [--width <px>] [--height <px>]
                                             Draw the scene at a moment and save a picture (agents use this to see their work)
  splash bake <scene-folder> <out.mov> [--width <px>] [--height <px>] [--fps <n>]
                                             Render one seamless loop into an HEVC video
  splash ask <scene-folder> "<request>" [--agent claude|codex|opencode] [--model <name>] [--effort <level>] [--attach <file>]...
                                             Ask an AI agent CLI (your own login, no API key) to change the scene; saves a version first
  splash desktop set <image>                 Set a picture as the wallpaper of every Space (saves your wallpaper settings first)
  splash desktop restore                     Put your previous wallpaper settings back
  splash doctor                              Check this Mac's power and system state
  splash version

Applying a scene to the desktop is done by the editor.
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func runInit(_ arguments: [String]) {
    guard let id = arguments.first, !id.hasPrefix("-") else { fail("Usage: splash init <id> [--name \"Display name\"] [--preset <id>]") }
    var name = id.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    if let flag = arguments.firstIndex(of: "--name"), arguments.indices.contains(flag + 1) { name = arguments[flag + 1] }
    var presetID = "gradient-drift"
    if let flag = arguments.firstIndex(of: "--preset"), arguments.indices.contains(flag + 1) { presetID = arguments[flag + 1] }
    guard let preset = Presets.find(presetID) else {
        fail("Unknown preset \"\(presetID)\". Available: \(Presets.all.map(\.id).joined(separator: ", "))")
    }

    let directory = URL(fileURLWithPath: id, isDirectory: true)
    if FileManager.default.fileExists(atPath: directory.path) { fail("\(id) already exists.") }

    do {
        try preset.install(at: directory, id: id, name: name)
    } catch {
        fail("Could not create the scene: \(error)")
    }
    print("Created \(id)/ from the \(preset.id) preset. Next: splash lint \(id)")
}

func runPresets(_ arguments: [String]) {
    if arguments.first == "export" {
        guard arguments.count > 1 else { fail("Usage: splash presets export <folder>") }
        let root = URL(fileURLWithPath: arguments[1], isDirectory: true)
        for preset in Presets.all {
            let target = root.appendingPathComponent(preset.id, isDirectory: true)
            try? FileManager.default.removeItem(at: target)
            do { try preset.install(at: target) } catch { fail("Could not write \(preset.id): \(error)") }
            print("wrote \(target.path)")
        }
        return
    }
    for preset in Presets.all {
        print("\(preset.id.padding(toLength: 16, withPad: " ", startingAt: 0)) \(preset.manifest.tiers.map(\.rawValue).joined(separator: "/").padding(toLength: 12, withPad: " ", startingAt: 0)) \(preset.summary)")
    }
}

func runLint(_ arguments: [String]) {
    guard let path = arguments.first else { fail("Usage: splash lint <scene-folder>") }
    let scene: Scene
    do {
        scene = try Scene.load(from: URL(fileURLWithPath: path, isDirectory: true))
    } catch {
        fail("\(error)")
    }
    let issues = SceneLinter.lint(scene)
    for issue in issues { print("\(issue.severity.rawValue): [\(issue.code)] \(issue.message)") }
    let errors = issues.filter { $0.severity == .error }.count
    let warnings = issues.count - errors
    print("\(scene.manifest.name): \(errors) error(s), \(warnings) warning(s)")
    exit(errors > 0 ? 1 : 0)
}

func option(_ name: String, in arguments: [String]) -> String? {
    guard let flag = arguments.firstIndex(of: name), arguments.indices.contains(flag + 1) else { return nil }
    return arguments[flag + 1]
}

/// Scenes are drawn by WebKit, which needs an application run loop. This runs `work` inside one and exits when it is done.
func runWithApplication(_ work: @escaping @MainActor () async throws -> Void) -> Never {
    MainActor.assumeIsolated {
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        Task { @MainActor in
            do {
                try await work()
                exit(0)
            } catch {
                fail("\(error)")
            }
        }
        application.run()
    }
    exit(0)
}

func loadSceneOrFail(_ path: String) -> Scene {
    do { return try Scene.load(from: URL(fileURLWithPath: path, isDirectory: true)) } catch { fail("\(error)") }
}

func runSnapshot(_ arguments: [String]) -> Never {
    guard arguments.count >= 2 else { fail("Usage: splash snapshot <scene-folder> <out.png> [--time <seconds>] [--width <px>] [--height <px>]") }
    let scene = loadSceneOrFail(arguments[0])
    let output = URL(fileURLWithPath: arguments[1])
    let time = option("--time", in: arguments).flatMap(Double.init) ?? 0
    let width = option("--width", in: arguments).flatMap(Double.init) ?? 1280
    let height = option("--height", in: arguments).flatMap(Double.init) ?? 720
    runWithApplication {
        let renderer = OffscreenRenderer(scene: scene, values: ParamStore.load(for: scene), size: CGSize(width: width, height: height))
        defer { renderer.close() }
        try await renderer.load()
        try OffscreenRenderer.writePNG(try await renderer.image(at: time), to: output)
        print("Saved \(output.path)")
    }
}

func runBake(_ arguments: [String]) -> Never {
    guard arguments.count >= 2 else { fail("Usage: splash bake <scene-folder> <out.mov> [--width <px>] [--height <px>] [--fps <n>]") }
    let scene = loadSceneOrFail(arguments[0])
    let output = URL(fileURLWithPath: arguments[1])
    runWithApplication {
        var options = BakeOptions.forMainScreen()
        if let width = option("--width", in: arguments).flatMap(Int.init) { options.width = width & ~1 }
        if let height = option("--height", in: arguments).flatMap(Int.init) { options.height = height & ~1 }
        if let fps = option("--fps", in: arguments).flatMap(Int.init) { options.fps = fps }
        var lastPercent = -1
        try await Baker.bake(scene: scene, values: ParamStore.load(for: scene), options: options, to: output) { fraction in
            let percent = Int(fraction * 100)
            if percent != lastPercent && percent % 10 == 0 { print("\(percent)%"); lastPercent = percent }
        }
        print("Saved \(output.path) (\(options.width)x\(options.height), \(options.fps) fps)")
    }
}

func runAsk(_ arguments: [String]) -> Never {
    guard arguments.count >= 2 else { fail("Usage: splash ask <scene-folder> \"<request>\" [--agent claude|codex|opencode]") }
    let scene = loadSceneOrFail(arguments[0])
    let installed = AgentLocator.installed()
    let kind = option("--agent", in: arguments).flatMap(AgentKind.init(rawValue:)) ?? installed.first
    if let kind, !kind.isEnabled { fail("\(kind.displayName) is switched off: it edited files outside the scene in testing. See docs/AGENTS_INTEGRATION.md.") }
    guard let kind, let executable = AgentLocator.find(kind) else {
        fail("No agent CLI found. Install Claude Code, Codex or OpenCode and sign in.")
    }
    do { try SceneHistory(scene: scene).snapshot(label: String(arguments[1].prefix(60))) } catch { fail("Could not save a version: \(error)") }
    var request = AgentRequest(text: arguments[1], splashCLI: RunnerControl.cliExecutable()?.path)
    // --attach <file> puts a file in the scene's assets to be used; --reference <file> only lets the agent look at it.
    for (flag, role) in [("--attach", AttachedFile.Role.use), ("--reference", AttachedFile.Role.reference)] {
        for index in arguments.indices where arguments[index] == flag && arguments.indices.contains(index + 1) {
            do {
                let semaphore = DispatchSemaphore(value: 0)
                var imported: AttachedFile?
                var failure: Error?
                Task {
                    do { imported = try await AttachmentImporter.importFile(URL(fileURLWithPath: arguments[index + 1]), role: role, into: scene) } catch { failure = error }
                    semaphore.signal()
                }
                semaphore.wait()
                if let failure { throw failure }
                if let imported { request.attachments.append(imported) }
            } catch {
                fail("Could not attach \(arguments[index + 1]): \(error.localizedDescription)")
            }
        }
    }
    let effort = option("--effort", in: arguments)
    if let effort, !kind.effortOptions.contains(where: { $0.value == effort }) {
        let known = kind.effortOptions.compactMap(\.value)
        fail(known.isEmpty ? "\(kind.displayName) has no effort setting here." : "Unknown effort \"\(effort)\" for \(kind.displayName). Use one of: \(known.joined(separator: ", ")).")
    }
    let session = AgentSession(kind: kind, executable: executable, request: request, sceneDirectory: scene.directory,
                               model: option("--model", in: arguments), effort: effort)
    print("Asking \(kind.displayName)…")
    session.start()
    let done = DispatchSemaphore(value: 0)
    var failed = false
    Task {
        for await event in session.events {
            switch event {
            case .text(let text): print(text)
            case .activity(let text): print("  · \(text)")
            case .finished(let success): if !success { failed = true }
            case .failed(let message): failed = true; FileHandle.standardError.write(Data((message + "\n").utf8))
            }
        }
        done.signal()
    }
    done.wait()
    if let reloaded = try? Scene.load(from: scene.directory) {
        let errors = SceneLinter.lint(reloaded).filter { $0.severity == .error }
        for issue in errors { print("error: [\(issue.code)] \(issue.message)") }
        exit(failed || !errors.isEmpty ? 1 : 0)
    }
    exit(failed ? 1 : 0)
}

func runDesktop(_ arguments: [String]) -> Never {
    let paths = AppPaths()
    switch arguments.first {
    case "set":
        guard arguments.count >= 2 else { fail("Usage: splash desktop set <image>") }
        let image = URL(fileURLWithPath: arguments[1])
        guard FileManager.default.fileExists(atPath: image.path) else { fail("No such file: \(image.path)") }
        runWithApplication {
            switch try await DesktopImage.applyEverywhere(image, in: paths) {
            case .spread(let spaces): print("Set on \(spaces) Spaces. Your previous settings are saved: splash desktop restore puts them back.")
            case .unsupported: print("Set on the Space on screen only (macOS's settings file was not changed).")
            }
        }
    case "restore":
        runWithApplication {
            if DesktopImage.restoreRemembered(in: paths) { print("Your previous wallpaper settings are back.") } else { print("Nothing saved to put back.") }
        }
    default:
        fail("Usage: splash desktop set <image> | splash desktop restore")
    }
}

func runDoctor() {
    let info = ProcessInfo.processInfo
    print("macOS: \(info.operatingSystemVersionString)")
    print("Low Power Mode: \(info.isLowPowerModeEnabled ? "on" : "off")")
    print("Thermal state: \(info.thermalState.rawValue) (0 nominal, 1 fair, 2 serious, 3 critical)")
    print("Memory: \(info.physicalMemory / 1_048_576) MB")
    let decision = PerformancePolicy.decide(
        sceneFPS: 30,
        state: SystemState(lowPowerMode: info.isLowPowerModeEnabled,
                           thermal: SystemState.Thermal(rawValue: info.thermalState.rawValue) ?? .nominal)
    )
    print("A 30 fps scene would now: \(decision)")
}

let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case "init": runInit(Array(arguments.dropFirst()))
case "lint": runLint(Array(arguments.dropFirst()))
case "presets": runPresets(Array(arguments.dropFirst()))
case "snapshot": runSnapshot(Array(arguments.dropFirst()))
case "bake": runBake(Array(arguments.dropFirst()))
case "ask": runAsk(Array(arguments.dropFirst()))
case "desktop": runDesktop(Array(arguments.dropFirst()))
case "doctor": runDoctor()
case "version", "--version": print(version)
case nil, "help", "--help", "-h": print(usage)
default: fail("Unknown command \"\(arguments[0])\".\n\n\(usage)")
}

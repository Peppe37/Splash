import AppKit
import SplashCore
import SplashPlatform

// splash-runner [scene-folder]
// The light process that draws the wallpaper. With no argument it shows what the editor applied (state.json).
// With a scene folder it shows that scene live, for development.
// It has no editor, no timers and no network: it wakes only when the system or the editor tells it something changed.

let paths = AppPaths()
let control = RunnerControl(paths: paths)

var developmentScene: Scene?
if CommandLine.arguments.count > 1 {
    do {
        developmentScene = try Scene.load(from: URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true))
    } catch {
        FileHandle.standardError.write(Data("\(error)\n".utf8))
        exit(1)
    }
}

// Only one runner at a time. A second one asks the first to reload, or, in development, replaces it.
if let other = control.runningPID(), other != getpid() {
    if developmentScene == nil {
        RunnerMessage.post(RunnerMessage.reload)
        exit(0)
    }
    RunnerMessage.post(RunnerMessage.quit)
    var waited = 0
    while control.runningPID() != nil, waited < 20 {
        usleep(100_000)
        waited += 1
    }
}

MainActor.assumeIsolated {
    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)
    let delegate = RunnerController(paths: paths, developmentScene: developmentScene)
    application.delegate = delegate
    application.run()
}

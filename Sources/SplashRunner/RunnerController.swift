import AppKit
import SplashCore
import SplashPlatform
import ServiceManagement

/// Owns the wallpaper windows. It reads what to show from `state.json`, and only when the editor says the file changed:
/// there is no timer and no polling anywhere in the runner.
@MainActor
final class RunnerController: NSObject, NSApplicationDelegate {
    private let paths: AppPaths
    private let control: RunnerControl
    private let monitor = SystemMonitor()
    private var settings = PowerSettings.load()
    /// A scene folder given on the command line, for development. It overrides state.json.
    private let developmentScene: Scene?

    private var windows: [WallpaperWindow] = []
    private var renderers: [ObjectIdentifier: WallpaperRenderer] = [:]
    private var occluded: Set<ObjectIdentifier> = []
    private var sceneFPS = 30
    private var userPaused = false
    private var statusItem: NSStatusItem?
    private var titleItem: NSMenuItem?
    private var pauseItem: NSMenuItem?
    private var loginItem: NSMenuItem?
    private var observers: [NSObjectProtocol] = []

    init(paths: AppPaths, developmentScene: Scene?) {
        self.paths = paths
        self.control = RunnerControl(paths: paths)
        self.developmentScene = developmentScene
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        control.registerCurrentProcess()
        buildStatusItem()
        listen()
        monitor.onChange = { [weak self] _ in self?.applyDecisions() }
        monitor.start()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                // A display was added or changed: give it the scene's picture as its real wallpaper, then cover it with a window.
                self?.applyStill()
                self?.show()
            }
        }
        show()
    }

    func applicationWillTerminate(_ notification: Notification) {
        control.unregisterCurrentProcess()
    }

    // MARK: - Messages from the editor

    private func listen() {
        let center = DistributedNotificationCenter.default()
        observers.append(center.addObserver(forName: RunnerMessage.reload, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.show() }
        })
        observers.append(center.addObserver(forName: RunnerMessage.settings, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.settings = PowerSettings.load()
                self?.applyDecisions()
            }
        })
        observers.append(center.addObserver(forName: RunnerMessage.quit, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { NSApplication.shared.terminate(nil) }
        })
        observers.append(center.addObserver(forName: RunnerMessage.values, object: nil, queue: .main) { [weak self] note in
            let json = note.userInfo?["values"] as? String
            MainActor.assumeIsolated {
                guard let json else { return }
                self?.renderers.values.forEach { $0.setParams(json: json) }
            }
        })
    }

    // MARK: - What is shown

    private func show() {
        tearDown()
        guard let target = currentTarget() else {
            // Nothing to draw (no scene, or a static one that is the real wallpaper already): do not stay around.
            if developmentScene == nil { NSApplication.shared.terminate(nil) }
            return
        }

        windows = NSScreen.screens.map { screen in
            let window = WallpaperWindow(screen: screen)
            let key = ObjectIdentifier(window)
            window.onOcclusionChange = { [weak self] covered in
                guard let self else { return }
                if covered { self.occluded.insert(key) } else { self.occluded.remove(key) }
                self.applyDecisions()
            }
            switch target {
            case .live(let scene, let json):
                renderers[key] = WebRenderer(window: window, scene: scene, paramsJSON: json)
            case .video(let url):
                renderers[key] = VideoRenderer(window: window, url: url)
            }
            window.orderBack(nil)
            return window
        }
        titleItem?.title = target.title
        applyDecisions()
    }

    private func applyStill() {
        guard developmentScene == nil, let path = ActiveWallpaper.load(from: paths)?.stillPath,
              FileManager.default.fileExists(atPath: path) else { return }
        try? DesktopImage.apply(URL(fileURLWithPath: path))
    }

    private func tearDown() {
        for window in windows {
            renderers[ObjectIdentifier(window)]?.apply(.suspend)
            window.close()
        }
        windows = []
        renderers = [:]
        occluded = []
    }

    private enum Target {
        case live(Scene, paramsJSON: String)
        case video(URL)

        var title: String {
            switch self {
            case .live(let scene, _): return scene.manifest.name
            case .video(let url): return url.deletingPathExtension().lastPathComponent
            }
        }
    }

    private func currentTarget() -> Target? {
        if let developmentScene {
            sceneFPS = developmentScene.manifest.fps
            return .live(developmentScene, paramsJSON: ParamStore.json(ParamStore.load(for: developmentScene)))
        }
        guard let wallpaper = ActiveWallpaper.load(from: paths) else { return nil }
        switch wallpaper.tier {
        case .static:
            return nil
        case .baked:
            guard let path = wallpaper.mediaPath, FileManager.default.fileExists(atPath: path) else { return nil }
            return .video(URL(fileURLWithPath: path))
        case .live:
            guard let scene = try? Scene.load(from: URL(fileURLWithPath: wallpaper.sceneDirectory, isDirectory: true)) else { return nil }
            sceneFPS = scene.manifest.fps
            return .live(scene, paramsJSON: ParamStore.json(ParamStore.load(for: scene)))
        }
    }

    // MARK: - Performance

    private func applyDecisions() {
        for window in windows {
            let key = ObjectIdentifier(window)
            var state = monitor.state
            state.occluded = occluded.contains(key)
            state.userPaused = userPaused
            renderers[key]?.apply(PerformancePolicy.decide(sceneFPS: sceneFPS, state: state, settings: settings))
        }
    }

    // MARK: - Menu bar

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "drop.fill", accessibilityDescription: "Splash")
        let menu = NSMenu()

        let title = NSMenuItem(title: "No wallpaper", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())

        let pause = NSMenuItem(title: "Pause", action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        menu.addItem(pause)

        let editor = NSMenuItem(title: "Open Splash…", action: #selector(openEditor), keyEquivalent: "")
        editor.target = self
        menu.addItem(editor)

        let login = NSMenuItem(title: "Start at login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        // Needs the runner to be an app bundle.
        login.isEnabled = Bundle.main.bundleURL.pathExtension == "app"
        login.state = login.isEnabled && SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        item.menu = menu
        statusItem = item
        titleItem = title
        pauseItem = pause
        loginItem = login
    }

    @objc private func togglePause() {
        userPaused.toggle()
        pauseItem?.title = userPaused ? "Resume" : "Pause"
        applyDecisions()
    }

    @objc private func openEditor() {
        guard let executable = RunnerControl.editorExecutable() else { return }
        if executable.path.contains(".app/") {
            let bundle = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            NSWorkspace.shared.openApplication(at: bundle, configuration: NSWorkspace.OpenConfiguration())
        } else {
            let process = Process()
            process.executableURL = executable
            try? process.run()
        }
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSSound.beep()
        }
        loginItem?.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }
}

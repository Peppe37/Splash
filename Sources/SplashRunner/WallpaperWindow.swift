import AVFoundation
import AppKit
import SplashCore
import SplashPlatform

/// One desktop-level window on one screen.
@MainActor
final class WallpaperWindow: NSWindow {
    var onOcclusionChange: ((Bool) -> Void)?

    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        setFrame(screen.frame, display: false)

        NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: self, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.onOcclusionChange?(!self.occlusionState.contains(.visible))
            }
        }
    }
}

/// Draws one kind of content into a window, and obeys the decisions of `PerformancePolicy`.
@MainActor
protocol WallpaperRenderer: AnyObject {
    func apply(_ decision: RenderDecision)
    func setParams(json: String)
}

/// A live scene. The web view exists only while it draws: `suspend` destroys it to give the memory back.
@MainActor
final class WebRenderer: WallpaperRenderer {
    private let window: WallpaperWindow
    private let scene: Scene
    private var paramsJSON: String
    private var webView: SceneWebView?

    init(window: WallpaperWindow, scene: Scene, paramsJSON: String) {
        self.window = window
        self.scene = scene
        self.paramsJSON = paramsJSON
    }

    func apply(_ decision: RenderDecision) {
        switch decision {
        case .run(let fps):
            if let webView {
                webView.setFPS(fps)
                webView.resumeScene()
            } else {
                build(fps: fps, startPaused: false)
            }
        case .pause:
            if let webView {
                webView.pauseScene()
            } else {
                // Nothing drawn yet: draw a few frames, then stop, so the desktop shows a picture and not a black screen.
                build(fps: 30, startPaused: true)
            }
        case .suspend:
            guard let webView else { return }
            webView.stopLoading()
            webView.removeFromSuperview()
            self.webView = nil
            window.contentView = nil
        }
    }

    private func build(fps: Int, startPaused: Bool) {
        let view = SceneWebView(scene: scene, fps: fps, paramsJSON: paramsJSON, startPaused: startPaused, detail: 2, frame: window.contentLayoutRect)
        view.autoresizingMask = [.width, .height]
        window.contentView = view
        webView = view
    }

    func setParams(json: String) {
        paramsJSON = json
        webView?.setParams(json: json)
    }
}

/// A baked loop, played with hardware decoding. The player exists only while it plays.
@MainActor
final class VideoRenderer: WallpaperRenderer {
    private let window: WallpaperWindow
    private let url: URL
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?

    init(window: WallpaperWindow, url: URL) {
        self.window = window
        self.url = url
    }

    func apply(_ decision: RenderDecision) {
        switch decision {
        case .run:
            if player == nil { build() }
            player?.play()
        case .pause:
            if player == nil { build() }
            player?.pause()
        case .suspend:
            looper?.disableLooping()
            player?.pause()
            player = nil
            looper = nil
            window.contentView = nil
        }
    }

    private func build() {
        let queuePlayer = AVQueuePlayer()
        queuePlayer.isMuted = true
        queuePlayer.preventsDisplaySleepDuringVideoPlayback = false
        queuePlayer.actionAtItemEnd = .none
        looper = AVPlayerLooper(player: queuePlayer, templateItem: AVPlayerItem(url: url))

        let view = NSView(frame: window.contentLayoutRect)
        view.autoresizingMask = [.width, .height]
        view.wantsLayer = true
        let layer = AVPlayerLayer(player: queuePlayer)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer?.addSublayer(layer)
        window.contentView = view
        player = queuePlayer
    }

    func setParams(json: String) {}
}

import AppKit
import SplashCore
import WebKit

/// Cancels every navigation that leaves the scene folder, unless the scene asked for the network.
final class SceneNavigationGuard: NSObject, WKNavigationDelegate {
    let allowNetwork: Bool
    var onFinish: (() -> Void)?
    var onFail: ((Error) -> Void)?

    init(allowNetwork: Bool) {
        self.allowNetwork = allowNetwork
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        let isFile = navigationAction.request.url?.isFileURL ?? false
        let allowed = isFile || allowNetwork
        Task { @MainActor in decisionHandler(allowed ? .allow : .cancel) }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onFinish?()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        onFail?(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        onFail?(error)
    }
}

/// A web view that shows one scene with the `splash` SDK injected. Used by the wallpaper runner, the editor preview and the baker,
/// so all three show exactly the same thing.
@MainActor
public final class SceneWebView: WKWebView {
    public let scene: Scene
    let navigationGuard: SceneNavigationGuard

    public init(scene: Scene, fps: Int, paramsJSON: String, startPaused: Bool = false, detail: Double = 2, frame: CGRect = .zero) {
        self.scene = scene
        self.navigationGuard = SceneNavigationGuard(allowNetwork: scene.manifest.permissions.network)

        let controller = WKUserContentController()
        controller.addUserScript(WKUserScript(
            source: SceneRuntimeScript.source(fps: fps, paramsJSON: paramsJSON, startPaused: startPaused, detail: detail),
            injectionTime: .atDocumentStart, forMainFrameOnly: true))

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        // A fresh store each time: a wallpaper must not keep cookies or caches around.
        configuration.websiteDataStore = .nonPersistent()

        super.init(frame: frame, configuration: configuration)
        navigationDelegate = navigationGuard
        setValue(false, forKey: "drawsBackground")
        loadFileURL(scene.entryURL, allowingReadAccessTo: scene.directory)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    public func setParams(json: String) {
        evaluateJavaScript("splash._setParams(\(json));")
    }

    public func setFPS(_ fps: Int) {
        evaluateJavaScript("splash._setFPS(\(fps));")
    }

    public func pauseScene() {
        evaluateJavaScript("splash._pause();")
    }

    public func resumeScene() {
        evaluateJavaScript("splash._resume();")
    }

    /// Waits until the page has loaded.
    public func waitUntilLoaded() async throws {
        if !isLoading, url != nil { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var finished = false
            navigationGuard.onFinish = {
                guard !finished else { return }
                finished = true
                continuation.resume()
            }
            navigationGuard.onFail = { error in
                guard !finished else { return }
                finished = true
                continuation.resume(throwing: error)
            }
        }
    }

    /// Fixes the scene's clock at `time` seconds and draws one frame. Returns the current `splash.time`.
    public func renderFrame(at time: Double) async {
        _ = try? await evaluateJavaScript("splash._renderAt(\(time));")
    }

    public func currentTime() async -> Double? {
        (try? await evaluateJavaScript("splash.time")) as? Double
    }
}

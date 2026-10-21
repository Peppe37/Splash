import AppKit
import SplashCore
import WebKit

public enum RenderError: Error, CustomStringConvertible {
    case loadFailed(String)
    case snapshotFailed
    case writerFailed(String)

    public var description: String {
        switch self {
        case .loadFailed(let message): return "The scene did not load: \(message)"
        case .snapshotFailed: return "Could not take a picture of the scene."
        case .writerFailed(let message): return "Could not write the video: \(message)"
        }
    }
}

/// Draws a scene into pictures, off screen. The baker and the static tier use it, and so does `splash snapshot`.
@MainActor
public final class OffscreenRenderer {
    public let size: CGSize
    private let window: NSWindow
    private let webView: SceneWebView
    /// Pixels per point of the window, so the picture comes out at exactly `size` pixels.
    private let scale: CGFloat

    /// `size` is in pixels of the output picture.
    public init(scene: Scene, values: [String: JSONValue], size: CGSize) {
        self.size = size
        scale = NSScreen.main?.backingScaleFactor ?? 2
        let points = CGSize(width: size.width / scale, height: size.height / scale)
        let frame = CGRect(origin: .zero, size: points)
        // A real window is needed or WebKit does not paint. It sits far outside every screen and never shows.
        window = NSWindow(contentRect: CGRect(x: -30_000, y: -30_000, width: points.width, height: points.height),
                          styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.hasShadow = false
        // It must never be seen: fully transparent, no zoom-in animation, and not listed in Mission Control or the Window menu. Without
        // this, a window ordered in while the app is on another Space shows up on the Space the user is working on.
        window.alphaValue = 0
        window.isOpaque = false
        window.backgroundColor = .clear
        window.animationBehavior = .none
        window.isExcludedFromWindowsMenu = true
        window.canHide = false
        window.collectionBehavior = [.transient, .stationary, .ignoresCycle, .fullScreenNone]
        // Detail 1: pictures and recordings use every pixel. Quality costs nothing here, and the result is kept.
        webView = SceneWebView(scene: scene, fps: 60, paramsJSON: ParamStore.json(values), detail: 1, frame: frame)
        window.contentView = webView
        window.orderBack(nil)
    }

    public func load() async throws {
        do {
            try await webView.waitUntilLoaded()
        } catch {
            throw RenderError.loadFailed(error.localizedDescription)
        }
        // Let the page run its first frame.
        try? await Task.sleep(nanoseconds: 150_000_000)
    }

    public func setParams(_ values: [String: JSONValue]) {
        webView.setParams(json: ParamStore.json(values))
    }

    /// The scene as it looks `time` seconds in.
    public func image(at time: Double) async throws -> CGImage {
        await webView.renderFrame(at: time)
        let configuration = WKSnapshotConfiguration()
        configuration.snapshotWidth = NSNumber(value: Double(size.width / scale))
        let image: NSImage = try await withCheckedThrowingContinuation { continuation in
            webView.takeSnapshot(with: configuration) { image, error in
                if let image { continuation.resume(returning: image) } else { continuation.resume(throwing: error ?? RenderError.snapshotFailed) }
            }
        }
        var rect = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { throw RenderError.snapshotFailed }
        return cgImage
    }

    public func close() {
        window.contentView = nil
        window.close()
    }

    public static func writePNG(_ image: CGImage, to url: URL) throws {
        let representation = NSBitmapImageRep(cgImage: image)
        guard let data = representation.representation(using: .png, properties: [:]) else { throw RenderError.snapshotFailed }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

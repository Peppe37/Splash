import AppKit
import SplashCore
import SplashPlatform
import Observation

struct Stroke: Identifiable {
    let id = UUID()
    /// Points as fractions of the preview: 0 is left or top, 1 is right or bottom.
    var points: [CGPoint]
}

struct Pin: Identifiable {
    let id = UUID()
    var x: Double
    var y: Double
    var text: String = ""
}

/// What the user draws and pins on the preview, to send with the next request to an agent.
@MainActor
@Observable
final class AnnotationModel {
    enum Tool: String, CaseIterable, Identifiable {
        case pen = "Draw"
        case pin = "Comment"
        var id: String { rawValue }
        var symbol: String { self == .pen ? "pencil.tip" : "mappin" }
    }

    var isActive = false
    var tool: Tool = .pen
    var strokes: [Stroke] = []
    var current: Stroke?
    var pins: [Pin] = []

    var isEmpty: Bool { strokes.isEmpty && pins.isEmpty }

    func reset() {
        isActive = false
        clear()
    }

    func clear() {
        strokes = []
        current = nil
        pins = []
    }

    func removePin(_ pin: Pin) {
        pins.removeAll { $0.id == pin.id }
    }

    /// A picture of the preview with the drawings and numbered pins on top, saved inside the scene folder so the agent can open it.
    /// Returns the file and the pin comments, with the time of the frame.
    func renderFrame(of webView: SceneWebView, scene: WallpaperScene) async throws -> (url: URL, comments: [Comment]) {
        let configuration = WKSnapshotConfigurationFactory.make(width: webView.bounds.width)
        let base: NSImage = try await withCheckedThrowingContinuation { continuation in
            webView.takeSnapshot(with: configuration) { image, error in
                if let image { continuation.resume(returning: image) } else { continuation.resume(throwing: error ?? RenderError.snapshotFailed) }
            }
        }
        let time = await webView.currentTime()
        let composed = compose(base: base)

        let folder = scene.directory.appendingPathComponent(ParamStore.hiddenFolder).appendingPathComponent("annotations", isDirectory: true)
        let url = folder.appendingPathComponent("frame-\(Int(Date().timeIntervalSince1970)).png")
        try OffscreenRenderer.writePNG(composed, to: url)

        let comments = pins.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }.map {
            Comment(x: $0.x, y: $0.y, time: time, text: $0.text)
        }
        return (url, comments)
    }

    private func compose(base: NSImage) -> CGImage {
        var rect = CGRect(origin: .zero, size: base.size)
        let baseImage = base.cgImage(forProposedRect: &rect, context: nil, hints: nil)!
        let width = baseImage.width, height = baseImage.height
        let scale = CGFloat(width) / 900
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(baseImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        func point(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * CGFloat(width), y: (1 - p.y) * CGFloat(height)) }

        context.setStrokeColor(NSColor.systemRed.cgColor)
        context.setLineWidth(max(3, 4 * scale))
        context.setLineCap(.round)
        context.setLineJoin(.round)
        for stroke in strokes where stroke.points.count > 1 {
            context.beginPath()
            context.move(to: point(stroke.points[0]))
            for p in stroke.points.dropFirst() { context.addLine(to: point(p)) }
            context.strokePath()
        }

        let graphics = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        let radius = max(12, 14 * scale)
        for (index, pin) in pins.enumerated() {
            let center = point(CGPoint(x: pin.x, y: pin.y))
            context.setFillColor(NSColor.systemRed.cgColor)
            context.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            let label = NSAttributedString(string: "\(index + 1)", attributes: [
                .font: NSFont.boldSystemFont(ofSize: radius * 1.1), .foregroundColor: NSColor.white,
            ])
            let size = label.size()
            label.draw(at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2))
        }
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()!
    }
}

import WebKit

enum WKSnapshotConfigurationFactory {
    @MainActor
    static func make(width: CGFloat) -> WKSnapshotConfiguration {
        let configuration = WKSnapshotConfiguration()
        configuration.snapshotWidth = NSNumber(value: Double(max(width, 300)))
        return configuration
    }
}

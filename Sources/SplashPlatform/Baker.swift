import AVFoundation
import AppKit
import SplashCore
import CoreVideo

public struct BakeOptions: Sendable {
    public var width: Int
    public var height: Int
    public var fps: Int
    public var bitRate: Int

    public init(width: Int, height: Int, fps: Int = 30, bitRate: Int = 14_000_000) {
        self.width = width
        self.height = height
        self.fps = fps
        self.bitRate = bitRate
    }

    /// The main screen's size in pixels, never above 2560 wide: a wallpaper does not need more, and a bigger video costs more to play.
    @MainActor
    public static func forMainScreen(fps: Int = 30) -> BakeOptions {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let scale = screen?.backingScaleFactor ?? 2
        let size = screen?.frame.size ?? CGSize(width: 1440, height: 900)
        var width = Int(size.width * scale), height = Int(size.height * scale)
        if width > 2560 {
            height = Int(Double(height) * 2560.0 / Double(width))
            width = 2560
        }
        return BakeOptions(width: width & ~1, height: height & ~1, fps: fps)
    }
}

/// Renders one seamless loop of a scene into an HEVC video. The scene is driven by its own clock (`splash.time`),
/// so the first frame and the frame after the last are the same and the loop has no jump.
public enum Baker {
    @MainActor
    public static func bake(scene: Scene, values: [String: JSONValue], options: BakeOptions, to output: URL,
                            progress: @escaping @MainActor (Double) -> Void = { _ in }) async throws {
        guard let loop = scene.manifest.loopSeconds, loop > 0 else {
            throw RenderError.writerFailed("The scene has no loopSeconds.")
        }
        let frameCount = Int((loop * Double(options.fps)).rounded())
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: output)

        let writer = try AVAssetWriter(outputURL: output, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: options.width,
            AVVideoHeightKey: options.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: options.bitRate,
                AVVideoExpectedSourceFrameRateKey: options.fps,
                AVVideoMaxKeyFrameIntervalKey: options.fps * 2,
            ],
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: options.width,
            kCVPixelBufferHeightKey as String: options.height,
        ])
        guard writer.canAdd(input) else { throw RenderError.writerFailed("The video format is not supported.") }
        writer.add(input)
        guard writer.startWriting() else { throw RenderError.writerFailed(writer.error?.localizedDescription ?? "unknown error") }
        writer.startSession(atSourceTime: .zero)

        let renderer = OffscreenRenderer(scene: scene, values: values, size: CGSize(width: options.width, height: options.height))
        defer { renderer.close() }
        try await renderer.load()

        for index in 0..<frameCount {
            try Task.checkCancellation()
            let time = Double(index) / Double(options.fps)
            let image = try await renderer.image(at: time)
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 5_000_000) }
            guard let pool = adaptor.pixelBufferPool, let buffer = makeBuffer(from: image, pool: pool, options: options) else {
                throw RenderError.writerFailed("Could not make a frame.")
            }
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: CMTimeScale(options.fps))) else {
                throw RenderError.writerFailed(writer.error?.localizedDescription ?? "append failed")
            }
            progress(Double(index + 1) / Double(frameCount))
        }

        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed {
            throw RenderError.writerFailed(writer.error?.localizedDescription ?? "the writer did not finish")
        }
    }

    private static func makeBuffer(from image: CGImage, pool: CVPixelBufferPool, options: BakeOptions) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer), width: options.width, height: options.height, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: options.width, height: options.height))
        return buffer
    }
}

import AVFoundation
import AppKit
import Foundation
import SplashCore

/// Brings a file the user chose into a scene's folder so an agent can use or look at it.
///
/// A file meant for the scene goes to `assets/`, where the scene can use it with a relative path. A file meant only as a reference goes
/// to `.splash/references/`, which is not part of the scene. For a video, a few pictures taken from it are saved too, because an agent
/// cannot play a video but can look at pictures. Copies are cheap on a Mac's disk (they share their data until one changes).
public enum AttachmentImporter {
    public struct Failure: LocalizedError {
        public let message: String
        public var errorDescription: String? { message }
    }

    /// Larger files are refused: they would make every saved version of the scene heavy.
    public static let maxBytes = 300 * 1024 * 1024
    public static let frameCount = 6

    public static func importFile(_ source: URL, role: AttachedFile.Role, into scene: Scene) async throws -> AttachedFile {
        let fileManager = FileManager.default
        let size = (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= maxBytes else {
            throw Failure(message: "\"\(source.lastPathComponent)\" is larger than \(maxBytes / 1_048_576) MB. Use a smaller file.")
        }
        let kind = AttachedFile.Kind.detect(extension: source.pathExtension)
        let folder = role == .use ? "assets" : "\(ParamStore.hiddenFolder)/references"
        let folderURL = scene.directory.appendingPathComponent(folder, isDirectory: true)
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let name = uniqueName(for: source.lastPathComponent, in: folderURL)
        let destination = folderURL.appendingPathComponent(name)
        try fileManager.copyItem(at: source, to: destination)

        var frames: [String] = []
        if kind == .video {
            let referencesURL = scene.directory.appendingPathComponent("\(ParamStore.hiddenFolder)/references", isDirectory: true)
            try fileManager.createDirectory(at: referencesURL, withIntermediateDirectories: true)
            let base = (name as NSString).deletingPathExtension
            frames = try await extractFrames(from: destination, base: base, into: referencesURL)
                .map { "\(ParamStore.hiddenFolder)/references/\($0)" }
        }
        return AttachedFile(path: "\(folder)/\(name)", role: role, kind: kind, frames: frames)
    }

    /// A name that is safe in a URL and not taken yet: "My file.svg" becomes "My-file.svg", then "My-file-2.svg" if that exists.
    static func uniqueName(for original: String, in folder: URL) -> String {
        // Only the file's own name counts, never a path, and a name must not start with a dot (that would hide the file).
        let original = (original as NSString).lastPathComponent
        let ext = (original as NSString).pathExtension.lowercased()
        let stem = (original as NSString).deletingPathExtension
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        var cleaned = String(stem.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
        while cleaned.contains("--") { cleaned = cleaned.replacingOccurrences(of: "--", with: "-") }
        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "-."))
        if cleaned.isEmpty { cleaned = "file" }
        func name(_ suffix: Int?) -> String {
            let base = suffix.map { "\(cleaned)-\($0)" } ?? cleaned
            return ext.isEmpty ? base : "\(base).\(ext)"
        }
        var candidate = name(nil), number = 2
        while FileManager.default.fileExists(atPath: folder.appendingPathComponent(candidate).path) {
            candidate = name(number)
            number += 1
        }
        return candidate
    }

    /// Pictures evenly spread over the video, saved as PNG. Returns their file names.
    static func extractFrames(from video: URL, base: String, into folder: URL) async throws -> [String] {
        let asset = AVURLAsset(url: video)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw Failure(message: "This video could not be read.") }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1280, height: 1280)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        var names: [String] = []
        for index in 0..<frameCount {
            let time = CMTime(seconds: duration * (Double(index) + 0.5) / Double(frameCount), preferredTimescale: 600)
            guard let image = try? await generator.image(at: time).image else { continue }
            let name = "\(base)-frame-\(index + 1).png"
            try writePNG(image, to: folder.appendingPathComponent(name))
            names.append(name)
        }
        guard !names.isEmpty else { throw Failure(message: "No picture could be taken from this video.") }
        return names
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw Failure(message: "Could not save a picture.")
        }
        try data.write(to: url, options: .atomic)
    }
}

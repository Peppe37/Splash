import AppKit
import Observation
import SplashCore
import SplashPlatform

/// Small pictures of scenes and presets for the library. They are drawn by the same code that draws the wallpaper, one at a time,
/// and kept on disk until the scene changes.
@MainActor
@Observable
final class ThumbnailStore {
    private let paths: AppPaths
    private(set) var images: [String: NSImage] = [:]
    private var keyByItem: [String: String] = [:]

    private struct Job {
        let key: String
        let scene: WallpaperScene
        let values: [String: SplashCore.JSONValue]
        let cleanup: URL?
    }
    private var queue: [Job] = []
    private var working = false

    init(paths: AppPaths) {
        self.paths = paths
    }

    func image(forScene id: String) -> NSImage? {
        keyByItem["scene:" + id].flatMap { images[$0] }
    }

    func image(forPreset id: String) -> NSImage? {
        keyByItem["preset:" + id].flatMap { images[$0] }
    }

    /// Makes sure every scene has an up-to-date picture. Scenes whose files did not change are not drawn again.
    func sync(_ scenes: [WallpaperScene]) {
        for scene in scenes {
            let key = "scene-\(scene.manifest.id)-\(scene.fingerprint())"
            guard keyByItem["scene:" + scene.manifest.id] != key else { continue }
            keyByItem["scene:" + scene.manifest.id] = key
            enqueue(Job(key: key, scene: scene, values: ParamStore.load(for: scene), cleanup: nil))
        }
    }

    func syncPresets(_ presets: [Preset]) {
        for preset in presets {
            let key = "preset-\(preset.id)-\(Self.hash(preset.files.values.sorted().joined()) )"
            guard keyByItem["preset:" + preset.id] != key else { continue }
            keyByItem["preset:" + preset.id] = key
            // A preset is not a folder on disk, so it is written to a temporary one to be drawn.
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("splash-thumb-\(preset.id)-\(UUID().uuidString)")
            guard let scene = try? preset.install(at: folder) else { continue }
            enqueue(Job(key: key, scene: scene, values: ParamStore.load(for: scene), cleanup: folder))
        }
    }

    private static func hash(_ text: String) -> String {
        var value: UInt64 = 5381
        for byte in text.utf8 { value = (value &* 33) ^ UInt64(byte) }
        return String(value, radix: 16)
    }

    private func enqueue(_ job: Job) {
        let file = paths.thumbnails.appendingPathComponent(job.key + ".png")
        if let cached = NSImage(contentsOf: file) {
            images[job.key] = cached
            if let cleanup = job.cleanup { try? FileManager.default.removeItem(at: cleanup) }
            return
        }
        queue.removeAll { $0.key == job.key }
        queue.append(job)
        if !working { Task { await pump() } }
    }

    private func pump() async {
        working = true
        defer { working = false }
        while !queue.isEmpty {
            let job = queue.removeFirst()
            let renderer = OffscreenRenderer(scene: job.scene, values: job.values, size: CGSize(width: 720, height: 450))
            do {
                try await renderer.load()
                let image = try await renderer.image(at: job.scene.manifest.stillTime)
                let file = paths.thumbnails.appendingPathComponent(job.key + ".png")
                try? OffscreenRenderer.writePNG(image, to: file)
                images[job.key] = NSImage(cgImage: image, size: NSSize(width: 360, height: 225))
            } catch {
                // No picture: the card keeps its placeholder.
            }
            renderer.close()
            if let cleanup = job.cleanup { try? FileManager.default.removeItem(at: cleanup) }
        }
    }
}

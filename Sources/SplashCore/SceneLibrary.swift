import Foundation

/// The user's scenes on disk.
public struct SceneLibrary: Sendable {
    public let paths: AppPaths

    public init(paths: AppPaths = AppPaths()) {
        self.paths = paths
    }

    /// Valid scenes only, sorted by name. A broken folder is skipped, not fatal.
    public func scenes() -> [Scene] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: paths.scenes.path)) ?? []
        return names.filter { !$0.hasPrefix(".") }.compactMap { name in
            try? Scene.load(from: paths.scenes.appendingPathComponent(name, isDirectory: true))
        }.sorted { $0.manifest.name.localizedCaseInsensitiveCompare($1.manifest.name) == .orderedAscending }
    }

    /// An id based on `base` that no scene uses yet: "waves", "waves-2", "waves-3".
    public func uniqueID(_ base: String) -> String {
        let cleaned = Self.slug(base)
        var candidate = cleaned
        var number = 2
        while FileManager.default.fileExists(atPath: paths.scenes.appendingPathComponent(candidate).path) {
            candidate = "\(cleaned)-\(number)"
            number += 1
        }
        return candidate
    }

    /// Lowercase words joined by dashes, as the linter wants.
    public static func slug(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased()
        let words = folded.split { !($0.isLetter || $0.isNumber) }.map(String.init)
        let joined = words.joined(separator: "-")
        return joined.isEmpty ? "scene" : joined
    }

    @discardableResult
    public func create(from preset: Preset, name: String? = nil) throws -> Scene {
        try paths.createDirectories()
        let displayName = name ?? preset.name
        let id = uniqueID(displayName)
        return try preset.install(at: paths.scenes.appendingPathComponent(id, isDirectory: true), id: id, name: displayName)
    }

    @discardableResult
    public func duplicate(_ scene: Scene, name: String) throws -> Scene {
        try paths.createDirectories()
        let id = uniqueID(name)
        let target = paths.scenes.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.copyItem(at: scene.directory, to: target)
        // The copy starts with a clean history.
        try? FileManager.default.removeItem(at: target.appendingPathComponent(ParamStore.hiddenFolder).appendingPathComponent("history"))
        var manifest = scene.manifest
        manifest.id = id
        manifest.name = name
        try Scene.write(manifest, to: target)
        return Scene(directory: target, manifest: manifest)
    }

    public func rename(_ scene: Scene, to name: String) throws -> Scene {
        var manifest = scene.manifest
        manifest.name = name
        try Scene.write(manifest, to: scene.directory)
        return Scene(directory: scene.directory, manifest: manifest)
    }

    public func delete(_ scene: Scene) throws {
        // Only ever delete inside the library folder.
        guard scene.directory.standardizedFileURL.path.hasPrefix(paths.scenes.standardizedFileURL.path + "/") else { return }
        try FileManager.default.removeItem(at: scene.directory)
    }
}

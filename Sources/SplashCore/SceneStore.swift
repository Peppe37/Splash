import Foundation

public enum SceneStoreError: Error, CustomStringConvertible {
    case missingManifest(URL)
    case unreadableManifest(URL, underlying: Error)

    public var description: String {
        switch self {
        case .missingManifest(let url):
            return "No scene.json in \(url.path)"
        case .unreadableManifest(let url, let underlying):
            return "Cannot read \(url.lastPathComponent): \(underlying)"
        }
    }
}

/// Loads a scene folder (a `.splashscene` package or any folder with a `scene.json`).
public struct Scene: Sendable {
    public static let manifestFileName = "scene.json"

    public let directory: URL
    public let manifest: SceneManifest

    public var entryURL: URL { directory.appendingPathComponent(manifest.entry) }

    public init(directory: URL, manifest: SceneManifest) {
        self.directory = directory
        self.manifest = manifest
    }

    public static func load(from directory: URL) throws -> Scene {
        let manifestURL = directory.appendingPathComponent(manifestFileName)
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw SceneStoreError.missingManifest(directory)
        }
        do {
            let data = try Data(contentsOf: manifestURL)
            let manifest = try JSONDecoder().decode(SceneManifest.self, from: data)
            return Scene(directory: directory, manifest: manifest)
        } catch {
            throw SceneStoreError.unreadableManifest(manifestURL, underlying: error)
        }
    }

    /// A value that changes when the scene's files or parameter values change. Used to know when a thumbnail is out of date.
    public func fingerprint() -> String {
        let fileManager = FileManager.default
        var parts: [String] = []
        let candidates = [directory, directory.appendingPathComponent(ParamStore.hiddenFolder)]
        for folder in candidates {
            let enumerator = fileManager.enumerator(at: folder, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                                                    options: folder == directory ? [.skipsHiddenFiles] : [.skipsSubdirectoryDescendants])
            for case let url as URL in enumerator ?? FileManager.DirectoryEnumerator() {
                if folder != directory, url.lastPathComponent != "values.json" { continue }
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isDirectoryKey])
                if values?.isDirectory == true { continue }
                parts.append("\(url.lastPathComponent):\(Int(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)):\(values?.fileSize ?? 0)")
            }
        }
        var hash: UInt64 = 5381
        for byte in parts.sorted().joined(separator: "|").utf8 { hash = (hash &* 33) ^ UInt64(byte) }
        return String(hash, radix: 16)
    }

    public static func write(_ manifest: SceneManifest, to directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoder.encode(manifest).write(to: directory.appendingPathComponent(manifestFileName))
    }
}

import Foundation

public struct LintIssue: Equatable, Sendable {
    public enum Severity: String, Sendable { case error, warning }

    public let severity: Severity
    public let code: String
    public let message: String

    public init(_ severity: Severity, _ code: String, _ message: String) {
        self.severity = severity
        self.code = code
        self.message = message
    }
}

/// Checks a scene before it is previewed or applied. Meant to be run by AI agents too:
/// every message says what is wrong and how to fix it.
public enum SceneLinter {
    static let idPattern = #"^[a-z0-9]+(-[a-z0-9]+)*$"#
    static let textExtensions: Set<String> = ["html", "htm", "js", "mjs", "css", "glsl", "frag", "vert", "svg"]

    public static func lint(_ scene: Scene) -> [LintIssue] {
        var issues: [LintIssue] = []
        let manifest = scene.manifest

        if manifest.schemaVersion != SceneManifest.currentSchemaVersion {
            issues.append(.init(.error, "schema-version",
                                "schemaVersion is \(manifest.schemaVersion), this build understands \(SceneManifest.currentSchemaVersion)."))
        }
        if manifest.id.range(of: idPattern, options: .regularExpression) == nil {
            issues.append(.init(.error, "id", "id \"\(manifest.id)\" must be lowercase words joined by dashes, like \"gradient-drift\"."))
        }
        if manifest.name.trimmingCharacters(in: .whitespaces).isEmpty {
            issues.append(.init(.error, "name", "name is empty."))
        }
        if !FileManager.default.fileExists(atPath: scene.entryURL.path) {
            issues.append(.init(.error, "entry", "entry file \"\(manifest.entry)\" does not exist."))
        }
        if manifest.entry.hasPrefix("/") || manifest.entry.contains("..") {
            issues.append(.init(.error, "entry-path", "entry must be a relative path inside the scene folder."))
        }
        if manifest.tiers.isEmpty {
            issues.append(.init(.error, "tiers", "tiers is empty. Use a list such as [\"baked\", \"live\"]."))
        }
        if manifest.tiers.contains(.baked) || manifest.tiers.contains(.static) {
            if manifest.loopSeconds == nil && manifest.tiers.contains(.baked) {
                issues.append(.init(.error, "loop-seconds", "tier \"baked\" needs loopSeconds, the length of one seamless loop."))
            }
        }
        if !(1...60).contains(manifest.fps) {
            issues.append(.init(.error, "fps", "fps must be between 1 and 60. The default is 30; lower is lighter."))
        } else if manifest.fps > 30 {
            issues.append(.init(.warning, "fps-high", "fps \(manifest.fps) costs battery. Use 30 or less unless the motion needs it."))
        }
        if manifest.permissions.audio && manifest.tiers != [.live] {
            issues.append(.init(.error, "audio-tier", "a scene that reacts to audio can only be live: set tiers to [\"live\"]."))
        }

        issues += lintParams(manifest.params)
        issues += lintSources(scene)
        return issues
    }

    static func lintParams(_ params: [SceneParam]) -> [LintIssue] {
        var issues: [LintIssue] = []
        var seen = Set<String>()
        for param in params {
            if !seen.insert(param.key).inserted {
                issues.append(.init(.error, "param-duplicate", "param key \"\(param.key)\" appears twice."))
            }
            switch param.type {
            case .number:
                guard let value = param.default.number else {
                    issues.append(.init(.error, "param-default", "param \"\(param.key)\" is a number but its default is not."))
                    continue
                }
                if param.min == nil || param.max == nil {
                    issues.append(.init(.error, "param-range", "param \"\(param.key)\" needs min and max so the editor can draw a slider."))
                } else if let low = param.min, let high = param.max, !(low <= value && value <= high) {
                    issues.append(.init(.error, "param-range", "param \"\(param.key)\" default \(value) is outside \(low)...\(high)."))
                }
            case .color:
                if param.default.string?.range(of: #"^#[0-9A-Fa-f]{6}$"#, options: .regularExpression) == nil {
                    issues.append(.init(.error, "param-default", "param \"\(param.key)\" is a color: default must look like \"#aa33ff\"."))
                }
            case .bool:
                if param.default.bool == nil {
                    issues.append(.init(.error, "param-default", "param \"\(param.key)\" is a bool but its default is not."))
                }
            case .choice:
                guard let options = param.options, !options.isEmpty else {
                    issues.append(.init(.error, "param-options", "param \"\(param.key)\" is a choice and needs a non-empty options list."))
                    continue
                }
                if let value = param.default.string, !options.contains(value) {
                    issues.append(.init(.error, "param-default", "param \"\(param.key)\" default \"\(value)\" is not in options."))
                }
            }
        }
        return issues
    }

    /// Looks for remote URLs in the scene code when the scene did not ask for the network.
    static func lintSources(_ scene: Scene) -> [LintIssue] {
        guard !scene.manifest.permissions.network else { return [] }
        guard let files = FileManager.default.enumerator(at: scene.directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return [] }
        var issues: [LintIssue] = []
        for case let url as URL in files where textExtensions.contains(url.pathExtension.lowercased()) {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                if line.element.contains("http://") || line.element.contains("https://") {
                    let relative = url.path.replacingOccurrences(of: scene.directory.path + "/", with: "")
                    issues.append(.init(.error, "network",
                                        "\(relative):\(line.offset + 1) uses a remote URL but permissions.network is false. Bundle the file in the scene folder, or set permissions.network to true."))
                }
            }
        }
        return issues
    }
}

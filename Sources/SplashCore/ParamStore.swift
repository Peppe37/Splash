import Foundation

/// The values the user chose for a scene's parameters. They live in the scene folder (`.splash/values.json`),
/// so they travel with the scene and the runner needs no other database.
public enum ParamStore {
    public static let hiddenFolder = ".splash"

    static func fileURL(for scene: Scene) -> URL {
        scene.directory.appendingPathComponent(hiddenFolder).appendingPathComponent("values.json")
    }

    /// Defaults from the manifest, overridden by saved values. Saved values that no longer fit are ignored.
    public static func load(for scene: Scene) -> [String: JSONValue] {
        var values: [String: JSONValue] = [:]
        for param in scene.manifest.params { values[param.key] = param.default }
        guard let data = try? Data(contentsOf: fileURL(for: scene)),
              let saved = try? JSONDecoder().decode([String: JSONValue].self, from: data) else { return values }
        for param in scene.manifest.params {
            if let value = saved[param.key], fits(value, param) { values[param.key] = value }
        }
        return values
    }

    public static func save(_ values: [String: JSONValue], for scene: Scene) throws {
        let url = fileURL(for: scene)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(values).write(to: url, options: .atomic)
    }

    public static func json(_ values: [String: JSONValue]) -> String {
        guard let data = try? JSONEncoder().encode(values), let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    static func fits(_ value: JSONValue, _ param: SceneParam) -> Bool {
        switch param.type {
        case .number:
            guard let number = value.number else { return false }
            if let low = param.min, number < low { return false }
            if let high = param.max, number > high { return false }
            return true
        case .color:
            return value.string?.range(of: #"^#[0-9A-Fa-f]{6}$"#, options: .regularExpression) != nil
        case .bool:
            return value.bool != nil
        case .choice:
            guard let text = value.string else { return false }
            return param.options?.contains(text) ?? false
        }
    }
}

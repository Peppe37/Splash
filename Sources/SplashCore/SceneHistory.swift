import Foundation

public struct HistoryEntry: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let date: Date
    public let label: String
}

/// Snapshots of a scene folder, kept inside it (`.splash/history`). One is taken before every AI turn
/// and before every restore, so any change can be undone.
public struct SceneHistory: Sendable {
    public static let keepLimit = 50
    let scene: Scene

    public init(scene: Scene) {
        self.scene = scene
    }

    private var historyDirectory: URL {
        scene.directory.appendingPathComponent(ParamStore.hiddenFolder).appendingPathComponent("history", isDirectory: true)
    }

    private static func makeID(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter.string(from: date)
    }

    @discardableResult
    public func snapshot(label: String, date: Date = Date()) throws -> HistoryEntry {
        let fileManager = FileManager.default
        let entry = HistoryEntry(id: Self.makeID(date), date: date, label: label)
        let target = historyDirectory.appendingPathComponent(entry.id, isDirectory: true)
        let files = target.appendingPathComponent("files", isDirectory: true)
        try fileManager.createDirectory(at: files, withIntermediateDirectories: true)

        for name in try fileManager.contentsOfDirectory(atPath: scene.directory.path) where !name.hasPrefix(".") {
            try fileManager.copyItem(at: scene.directory.appendingPathComponent(name), to: files.appendingPathComponent(name))
        }
        try JSONEncoder().encode(entry).write(to: target.appendingPathComponent("meta.json"))
        try prune()
        return entry
    }

    /// Newest first.
    public func entries() -> [HistoryEntry] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: historyDirectory.path)) ?? []
        return names.compactMap { name in
            guard let data = try? Data(contentsOf: historyDirectory.appendingPathComponent(name).appendingPathComponent("meta.json")) else { return nil }
            return try? JSONDecoder().decode(HistoryEntry.self, from: data)
        }.sorted { $0.id > $1.id }
    }

    /// Puts the scene back as it was. The current state is saved first, so the restore can be undone too.
    public func restore(_ entry: HistoryEntry) throws {
        let fileManager = FileManager.default
        let files = historyDirectory.appendingPathComponent(entry.id).appendingPathComponent("files")
        guard fileManager.fileExists(atPath: files.path) else { return }
        try snapshot(label: "Before restoring \"\(entry.label)\"")

        for name in try fileManager.contentsOfDirectory(atPath: scene.directory.path) where !name.hasPrefix(".") {
            try fileManager.removeItem(at: scene.directory.appendingPathComponent(name))
        }
        for name in try fileManager.contentsOfDirectory(atPath: files.path) {
            try fileManager.copyItem(at: files.appendingPathComponent(name), to: scene.directory.appendingPathComponent(name))
        }
    }

    private func prune() throws {
        for entry in entries().dropFirst(Self.keepLimit) {
            try? FileManager.default.removeItem(at: historyDirectory.appendingPathComponent(entry.id))
        }
    }
}

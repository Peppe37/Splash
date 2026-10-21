import Foundation
import SplashCore
import Testing
@testable import SplashPlatform

@Suite("AttachmentImporter")
struct AttachmentImporterTests {
    private func makeScene() throws -> (Scene, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("splash-attach-\(UUID().uuidString)")
        let scene = try Presets.find("blank")!.install(at: root.appendingPathComponent("scene"))
        return (scene, root)
    }

    @Test func namesAreSafeAndNeverOverwrite() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("splash-names-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        #expect(AttachmentImporter.uniqueName(for: "My Fox (final).SVG", in: folder) == "My-Fox-final.svg")
        try Data().write(to: folder.appendingPathComponent("fox.png"))
        #expect(AttachmentImporter.uniqueName(for: "fox.png", in: folder) == "fox-2.png")
        #expect(AttachmentImporter.uniqueName(for: "***.png", in: folder) == "file.png")
        #expect(AttachmentImporter.uniqueName(for: "../../evil.png", in: folder) == "evil.png")
    }

    @Test func aFileForTheSceneGoesToAssets() async throws {
        let (scene, root) = try makeScene()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Hero Fox.png")
        try Data([1, 2, 3]).write(to: source)

        let file = try await AttachmentImporter.importFile(source, role: .use, into: scene)

        #expect(file.path == "assets/Hero-Fox.png")
        #expect(file.kind == .image)
        #expect(file.role == .use)
        #expect(FileManager.default.fileExists(atPath: scene.directory.appendingPathComponent(file.path).path))
        // The original is left alone.
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    @Test func aReferenceStaysOutOfTheScene() async throws {
        let (scene, root) = try makeScene()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("mood.svg")
        try "<svg xmlns='x'/>".write(to: source, atomically: true, encoding: .utf8)

        let file = try await AttachmentImporter.importFile(source, role: .reference, into: scene)

        #expect(file.path == ".splash/references/mood.svg")
        #expect(file.kind == .svg)
        #expect(!FileManager.default.fileExists(atPath: scene.directory.appendingPathComponent("assets/mood.svg").path))
    }

    @Test func importedReferencesDoNotChangeWhatIsInTheLintedFiles() async throws {
        let (scene, root) = try makeScene()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("note.svg")
        // A remote address in a reference file must not fail the scene's network check: references are not part of the scene.
        try "<svg><a href='https://example.com'/></svg>".write(to: source, atomically: true, encoding: .utf8)
        _ = try await AttachmentImporter.importFile(source, role: .reference, into: scene)
        #expect(!SceneLinter.lint(try Scene.load(from: scene.directory)).contains { $0.code == "network" })
    }
}

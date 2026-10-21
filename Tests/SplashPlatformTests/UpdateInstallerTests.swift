import Foundation
import Testing
@testable import SplashPlatform

@Suite("UpdateInstaller")
struct UpdateInstallerTests {
    @Test func downloadsOnlyFromTheProjectReleases() {
        #expect(UpdateInstaller.downloadURL(version: "0.1.1-alpha")?.absoluteString
                == "https://github.com/Peppe37/Splash/releases/download/v0.1.1-alpha/Splash-0.1.1-alpha.dmg")
        #expect(UpdateInstaller.downloadURL(version: "1.0.0") != nil)
        #expect(UpdateInstaller.downloadURL(version: "") == nil)
        #expect(UpdateInstaller.downloadURL(version: "../../evil") == nil)
        #expect(UpdateInstaller.downloadURL(version: "0.1.1/../../x") == nil)
        #expect(UpdateInstaller.downloadURL(version: "0.1.1-alpha?x=1") == nil)
    }

    @Test func onlyTheSameCertificateCounts() {
        let mine = #"designated => identifier "com.giuseppe.splash.editor" and certificate leaf = H"aa11""#
        let other = #"designated => identifier "com.giuseppe.splash.editor" and certificate leaf = H"bb22""#
        let adHoc = #"designated => cdhash H"cc33""#
        #expect(UpdateInstaller.identitiesMatch(running: mine, update: mine))
        #expect(!UpdateInstaller.identitiesMatch(running: mine, update: other))
        // An ad-hoc signature is different on every build, so an update signed that way would ask for every permission again.
        #expect(!UpdateInstaller.identitiesMatch(running: adHoc, update: adHoc))
        #expect(!UpdateInstaller.identitiesMatch(running: mine, update: adHoc))
        #expect(!UpdateInstaller.identitiesMatch(running: nil, update: mine))
        #expect(!UpdateInstaller.identitiesMatch(running: mine, update: nil))
    }

    @Test func aCopyOutsideAFolderYouCanWriteToCannotBeReplaced() {
        #expect(!UpdateInstaller.canReplace(app: URL(fileURLWithPath: "/usr/bin/true")))   // not an app
        #expect(!UpdateInstaller.canReplace(app: URL(fileURLWithPath: "/System/Applications/Calculator.app")))
    }

    // MARK: - The swap script

    /// Runs the swap script with a process id that no longer exists, and returns what is left in the folder.
    private func swap(newApp: String?, in folder: URL, runner: String = "0") throws -> (opened: [String], status: Int32) {
        let finished = Process()
        finished.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try finished.run()
        finished.waitUntilExit()

        // A stand-in for `open` that only writes down what it was asked to open, so no app starts during the test.
        let log = folder.appendingPathComponent("opened.log")
        let opener = folder.appendingPathComponent("fake-open.sh")
        try "#!/bin/sh\necho \"$1\" >> \"\(log.path)\"\n".write(to: opener, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: opener.path)

        let work = folder.appendingPathComponent("work")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", UpdateInstaller.swapScript, "sh", String(finished.processIdentifier),
                             folder.appendingPathComponent("Splash.app").path,
                             newApp ?? folder.appendingPathComponent("Missing.app").path, work.path, runner, opener.path]
        try process.run()
        process.waitUntilExit()
        let opened = ((try? String(contentsOf: log, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
        return (opened, process.terminationStatus)
    }

    private func makeApp(at url: URL, marker: String) throws {
        try FileManager.default.createDirectory(at: url.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try marker.write(to: url.appendingPathComponent("Contents/marker"), atomically: true, encoding: .utf8)
    }

    @Test func swapReplacesTheAppAndOpensTheNewOne() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("splash-swap-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try makeApp(at: folder.appendingPathComponent("Splash.app"), marker: "old")
        try makeApp(at: folder.appendingPathComponent("staged/Splash.app"), marker: "new")

        let result = try swap(newApp: folder.appendingPathComponent("staged/Splash.app").path, in: folder, runner: "1")

        #expect(try String(contentsOf: folder.appendingPathComponent("Splash.app/Contents/marker"), encoding: .utf8) == "new")
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("Splash.app.old").path))
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("work").path))
        #expect(result.opened.count == 2)
        #expect(result.opened.first?.hasSuffix("Splash.app") == true)
        #expect(result.opened.last?.hasSuffix("Splash Runner.app") == true)
    }

    @Test func swapDoesNotStartTheRunnerIfItWasNotRunning() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("splash-swap-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try makeApp(at: folder.appendingPathComponent("Splash.app"), marker: "old")
        try makeApp(at: folder.appendingPathComponent("staged/Splash.app"), marker: "new")
        let result = try swap(newApp: folder.appendingPathComponent("staged/Splash.app").path, in: folder, runner: "0")
        #expect(result.opened.count == 1)
    }

    @Test func swapPutsTheOldAppBackIfTheCopyFails() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("splash-swap-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try makeApp(at: folder.appendingPathComponent("Splash.app"), marker: "old")

        // The new app does not exist, so the copy fails.
        _ = try swap(newApp: nil, in: folder)

        #expect(try String(contentsOf: folder.appendingPathComponent("Splash.app/Contents/marker"), encoding: .utf8) == "old")
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("Splash.app.old").path))
    }
}

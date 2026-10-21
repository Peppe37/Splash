import SplashCore
import SplashPlatform
import Foundation
import Observation

struct ChatMessage: Identifiable, Equatable {
    enum Kind { case user, agent, activity, error, note }
    let id = UUID()
    var kind: Kind
    var text: String
    var imagePath: String?
}

/// One conversation with an agent CLI about one scene.
@MainActor
@Observable
final class ChatModel {
    var messages: [ChatMessage] = []
    var isRunning = false
    var agent: AgentKind {
        didSet { UserDefaults.standard.set(agent.rawValue, forKey: "agent") }
    }

    private unowned let app: AppModel
    private let sceneID: String
    private var session: AgentSession?

    init(app: AppModel, sceneID: String) {
        self.app = app
        self.sceneID = sceneID
        let saved = UserDefaults.standard.string(forKey: "agent").flatMap(AgentKind.init(rawValue:))
        let installed = AgentLocator.installed()
        agent = saved.flatMap { installed.contains($0) ? $0 : nil } ?? installed.first ?? .claude
    }

    var installedAgents: [AgentKind] { AgentLocator.installed() }

    func send(_ text: String, includeAnnotations: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isRunning, let scene = app.scenes.first(where: { $0.manifest.id == sceneID }) else { return }
        guard let executable = AgentLocator.find(agent) else {
            messages.append(ChatMessage(kind: .error, text: "\(agent.displayName) is not installed. Install it and sign in, then try again. Splash uses the agent you already have: it never asks for an API key."))
            return
        }
        isRunning = true
        Task { await run(trimmed, scene: scene, executable: executable, includeAnnotations: includeAnnotations) }
    }

    func cancel() {
        session?.cancel()
    }

    private func run(_ text: String, scene: WallpaperScene, executable: URL, includeAnnotations: Bool) async {
        defer { isRunning = false; session = nil }

        // Save the scene first, so the whole turn can be undone from the History tab.
        _ = try? SceneHistory(scene: scene).snapshot(label: String(text.prefix(60)))

        var request = AgentRequest(text: text, splashCLI: RunnerControl.cliExecutable()?.path)
        var shownImage: String?
        if includeAnnotations, !app.annotations.isEmpty, let webView = app.preview.webView {
            do {
                let frame = try await app.annotations.renderFrame(of: webView, scene: scene)
                request.annotatedImage = frame.url
                request.comments = frame.comments
                shownImage = frame.url.path
            } catch {
                messages.append(ChatMessage(kind: .note, text: "Could not capture the drawing, sending the text only."))
            }
        }
        messages.append(ChatMessage(kind: .user, text: text, imagePath: shownImage))
        if shownImage != nil { app.annotations.clear(); app.annotations.isActive = false }

        // Make sure the folder explains the rules, even for scenes made by hand.
        let agentsFile = scene.directory.appendingPathComponent("AGENTS.md")
        if !FileManager.default.fileExists(atPath: agentsFile.path) {
            try? SceneTemplates.agentsMarkdown.write(to: agentsFile, atomically: true, encoding: .utf8)
        }

        let session = AgentSession(kind: agent, executable: executable, request: request, sceneDirectory: scene.directory)
        self.session = session
        session.start()

        for await event in session.events {
            switch event {
            case .text(let line):
                if let last = messages.last, last.kind == .agent {
                    messages[messages.count - 1].text += "\n" + line
                } else {
                    messages.append(ChatMessage(kind: .agent, text: line))
                }
            case .activity(let line):
                messages.append(ChatMessage(kind: .activity, text: line))
                if line.hasPrefix("Write") || line.hasPrefix("Edit") { app.reloadWhileAgentWorks() }
            case .finished(let success):
                if !success { messages.append(ChatMessage(kind: .error, text: "The agent reported an error.")) }
            case .failed(let message):
                messages.append(ChatMessage(kind: .error, text: message))
            }
        }

        guard app.selectedID == sceneID else { return }
        app.reloadSelectedFromDisk()
        let errors = app.issues.filter { $0.severity == .error }
        if errors.isEmpty {
            messages.append(ChatMessage(kind: .note, text: "Scene checks passed. Undo from the History tab if you do not like it."))
        } else {
            messages.append(ChatMessage(kind: .error, text: "The scene has \(errors.count) problem(s): \(errors[0].message)"))
        }
    }
}

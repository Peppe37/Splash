import Foundation
import Observation
import SplashCore
import SplashPlatform

struct ChatMessage: Identifiable, Equatable {
    enum Kind { case user, agent, activity, error, note }
    let id = UUID()
    var kind: Kind
    var text: String
    var imagePath: String?
    /// Names of files sent with a request.
    var attachments: [String] = []
}

/// A file the user chose but has not sent yet.
struct PendingAttachment: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    var role: AttachedFile.Role
    var kind: AttachedFile.Kind { AttachedFile.Kind.detect(extension: url.pathExtension) }
}

/// One conversation with an agent CLI about one scene.
@MainActor
@Observable
final class ChatModel {
    var messages: [ChatMessage] = []
    var isRunning = false
    var attachments: [PendingAttachment] = []
    var agent: AgentKind {
        didSet { UserDefaults.standard.set(agent.rawValue, forKey: "agent") }
    }
    /// The model chosen for each agent. Empty means the agent's own default.
    private(set) var models: [String: String]

    private unowned let app: AppModel
    private let sceneID: String
    private var session: AgentSession?

    init(app: AppModel, sceneID: String) {
        self.app = app
        self.sceneID = sceneID
        let saved = UserDefaults.standard.string(forKey: "agent").flatMap(AgentKind.init(rawValue:))
        let installed = AgentLocator.installed()
        agent = saved.flatMap { installed.contains($0) ? $0 : nil } ?? installed.first ?? .claude
        models = Dictionary(uniqueKeysWithValues: AgentKind.allCases.map { ($0.rawValue, UserDefaults.standard.string(forKey: "agentModel.\($0.rawValue)") ?? "") })
    }

    var installedAgents: [AgentKind] { AgentLocator.installed() }

    /// The model for the current agent, as typed or picked. Empty means the agent's own default.
    var model: String { models[agent.rawValue] ?? "" }

    func setModel(_ value: String) {
        models[agent.rawValue] = value
        UserDefaults.standard.set(value, forKey: "agentModel.\(agent.rawValue)")
    }

    /// What the user sees: "Sonnet", or the name they typed, or "Default".
    var modelLabel: String {
        if model.isEmpty { return "Default" }
        return agent.modelOptions.first { $0.value == model }?.label ?? model
    }

    // MARK: - Attachments

    func attach(_ urls: [URL]) {
        for url in urls where url.isFileURL && !attachments.contains(where: { $0.url == url }) {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else { continue }
            // A video is kept as a reference by default: a scene with a video can only be live. Anything else is meant for the scene.
            let role: AttachedFile.Role = AttachedFile.Kind.detect(extension: url.pathExtension) == .video ? .reference : .use
            attachments.append(PendingAttachment(url: url, role: role))
        }
    }

    func setRole(_ role: AttachedFile.Role, for id: UUID) {
        if let index = attachments.firstIndex(where: { $0.id == id }) { attachments[index].role = role }
    }

    func removeAttachment(_ id: UUID) {
        attachments.removeAll { $0.id == id }
    }

    // MARK: - Sending

    func send(_ text: String, includeAnnotations: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isRunning, let scene = app.scenes.first(where: { $0.manifest.id == sceneID }) else { return }
        guard let executable = AgentLocator.find(agent) else {
            messages.append(ChatMessage(kind: .error, text: "\(agent.displayName) is not installed. Install it and sign in, then try again. Splash uses the agent you already have: it never asks for an API key."))
            return
        }
        isRunning = true
        let pending = attachments
        attachments = []
        Task { await run(trimmed, scene: scene, executable: executable, includeAnnotations: includeAnnotations, pending: pending) }
    }

    func cancel() {
        session?.cancel()
    }

    private func run(_ text: String, scene: WallpaperScene, executable: URL, includeAnnotations: Bool, pending: [PendingAttachment]) async {
        defer { isRunning = false; session = nil }

        // Save the scene first, so the whole turn can be undone from the Versions tab.
        _ = try? SceneHistory(scene: scene).snapshot(label: String(text.prefix(60)))

        var request = AgentRequest(text: text, splashCLI: RunnerControl.cliExecutable()?.path)

        // Bring the files into the scene's folder: into assets/ to be used, or into .splash/references/ to be looked at.
        for item in pending {
            do {
                request.attachments.append(try await AttachmentImporter.importFile(item.url, role: item.role, into: scene))
            } catch {
                messages.append(ChatMessage(kind: .error, text: error.localizedDescription))
                return
            }
        }

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
        messages.append(ChatMessage(kind: .user, text: text, imagePath: shownImage,
                                    attachments: pending.map { "\($0.url.lastPathComponent) (\($0.role == .use ? "in the scene" : "reference"))" }))
        messages.append(ChatMessage(kind: .note, text: "Asking \(agent.displayName) (\(agent.provider)), model: \(modelLabel)"))
        if shownImage != nil { app.annotations.clear(); app.annotations.isActive = false }

        // Make sure the folder explains the rules, even for scenes made by hand.
        let agentsFile = scene.directory.appendingPathComponent("AGENTS.md")
        if !FileManager.default.fileExists(atPath: agentsFile.path) {
            try? SceneTemplates.agentsMarkdown.write(to: agentsFile, atomically: true, encoding: .utf8)
        }

        let session = AgentSession(kind: agent, executable: executable, request: request, sceneDirectory: scene.directory,
                                   model: model.isEmpty ? nil : model)
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
            messages.append(ChatMessage(kind: .note, text: "Scene checks passed. Undo from the Versions tab if you do not like it."))
        } else {
            messages.append(ChatMessage(kind: .error, text: "The scene has \(errors.count) problem(s): \(errors[0].message)"))
        }
    }
}

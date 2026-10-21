import Foundation

/// The agent CLIs Splash can drive. Each one is run as a subprocess with the user's own login: Splash never sees an API key.
public enum AgentKind: String, CaseIterable, Identifiable, Sendable {
    case claude, codex, opencode

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        case .opencode: return "OpenCode"
        }
    }

    public var executableName: String { rawValue }

    /// The company whose models the agent uses, so the user always sees who is going to read the prompt.
    public var provider: String {
        switch self {
        case .claude: return "Anthropic"
        case .codex: return "OpenAI"
        case .opencode: return "chosen in OpenCode"
        }
    }

    public struct ModelOption: Equatable, Hashable, Sendable {
        public let label: String
        /// What is passed to the agent as the model. Nil means: the agent's own choice.
        public let value: String?
    }

    /// Models worth offering in a menu. Anything else can be typed in. Model names change often, so the list stays short:
    /// aliases the agent resolves to its latest model, and "the agent's own default".
    public var modelOptions: [ModelOption] {
        switch self {
        case .claude:
            return [ModelOption(label: "Default", value: nil), ModelOption(label: "Fable", value: "fable"),
                    ModelOption(label: "Opus", value: "opus"), ModelOption(label: "Sonnet", value: "sonnet"),
                    ModelOption(label: "Haiku", value: "haiku")]
        case .codex, .opencode:
            return [ModelOption(label: "Default", value: nil)]
        }
    }

    public struct EffortOption: Equatable, Hashable, Sendable {
        public let label: String
        /// What is passed to the agent. Nil means: the agent's own default.
        public let value: String?
    }

    /// How hard the model should think. Claude Code takes it as `--effort` (checked against its `--help`). Codex takes it as the
    /// configuration value `model_reasoning_effort` (from its documentation: not tested, Codex is not installed on the development
    /// machine). OpenCode ties it to a model "variant" and has no setting of its own, so nothing is offered for it.
    public var effortOptions: [EffortOption] {
        switch self {
        case .claude:
            return [EffortOption(label: "Default", value: nil), EffortOption(label: "Low", value: "low"),
                    EffortOption(label: "Medium", value: "medium"), EffortOption(label: "High", value: "high"),
                    EffortOption(label: "Extra high", value: "xhigh"), EffortOption(label: "Max", value: "max")]
        case .codex:
            return [EffortOption(label: "Default", value: nil), EffortOption(label: "Low", value: "low"),
                    EffortOption(label: "Medium", value: "medium"), EffortOption(label: "High", value: "high")]
        case .opencode:
            return []
        }
    }

    /// The hint for the box where a model name can be typed.
    public var modelHint: String {
        switch self {
        case .claude: return "a model name, such as claude-sonnet-5-5"
        case .codex: return "a model name"
        case .opencode: return "provider/model, such as anthropic/claude-sonnet-5-5"
        }
    }

    /// OpenCode is switched off: in testing its `run` command edited a folder outside the scene (it works in its own
    /// project directory, and the command has no option to set one). Set SPLASH_ENABLE_OPENCODE=1 to try it anyway.
    public var isEnabled: Bool {
        switch self {
        case .claude, .codex: return true
        case .opencode: return ProcessInfo.processInfo.environment["SPLASH_ENABLE_OPENCODE"] == "1"
        }
    }

    /// Arguments for one non-interactive turn. The working directory is the scene folder.
    /// Claude Code is checked against its current `--help`; Codex is not installed on the development machine, so its flags are unverified.
    public func arguments(prompt: String, imagePaths: [String], splashCLI: String?, model: String? = nil, effort: String? = nil) -> [String] {
        let model = model?.trimmingCharacters(in: .whitespaces).nilIfEmpty
        // Only a level the agent is known to take is passed on.
        let effort = effort.flatMap { level in effortOptions.contains { $0.value == level } ? level : nil }
        switch self {
        case .claude:
            var tools = "Read,Edit,Write,Glob,Grep"
            if let splashCLI { tools += ",Bash(\(splashCLI):*)" }
            var arguments = ["-p", prompt, "--output-format", "stream-json", "--verbose", "--permission-mode", "acceptEdits"]
            if let model { arguments += ["--model", model] }
            if let effort { arguments += ["--effort", effort] }
            // --allowedTools takes a list, so it goes last.
            return arguments + ["--allowedTools", tools]
        case .codex:
            var arguments = ["exec", "--sandbox", "workspace-write", "--skip-git-repo-check"]
            if let model { arguments += ["--model", model] }
            if let effort { arguments += ["-c", "model_reasoning_effort=\"\(effort)\""] }
            for path in imagePaths { arguments += ["--image", path] }
            return arguments + [prompt]
        case .opencode:
            // --standalone: without it OpenCode talks to a background service that works in its own folder, not in the scene's.
            var arguments = ["run", prompt, "--auto", "--standalone"]
            if let model { arguments += ["--model", model] }
            for path in imagePaths { arguments += ["--file", path] }
            return arguments
        }
    }

    var emitsStreamJSON: Bool { self == .claude }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

public enum AgentEvent: Equatable, Sendable {
    /// Something the agent said.
    case text(String)
    /// Something the agent did, such as "Edit index.html".
    case activity(String)
    case finished(success: Bool)
    case failed(String)
}

/// Turns one line of agent output into events. Pure, so it can be tested without running an agent.
public enum AgentOutputParser {
    public static func parse(line: String, kind: AgentKind) -> [AgentEvent] {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard kind.emitsStreamJSON else { return [.text(trimmed)] }
        guard let data = trimmed.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = object["type"] as? String else { return [.text(trimmed)] }

        switch type {
        case "assistant":
            guard let message = object["message"] as? [String: Any], let content = message["content"] as? [[String: Any]] else { return [] }
            return content.compactMap { item in
                switch item["type"] as? String {
                case "text":
                    guard let text = item["text"] as? String, !text.isEmpty else { return nil }
                    return .text(text)
                case "tool_use":
                    return .activity(describeTool(item))
                default:
                    return nil
                }
            }
        case "result":
            let failed = (object["is_error"] as? Bool) ?? false
            return [.finished(success: !failed)]
        default:
            return []
        }
    }

    static func describeTool(_ item: [String: Any]) -> String {
        let name = (item["name"] as? String) ?? "Tool"
        let input = item["input"] as? [String: Any] ?? [:]
        if let path = input["file_path"] as? String ?? input["path"] as? String {
            return "\(name) \((path as NSString).lastPathComponent)"
        }
        if let command = input["command"] as? String { return "\(name) \(command.prefix(60))" }
        if let pattern = input["pattern"] as? String { return "\(name) \(pattern.prefix(60))" }
        return name
    }
}

/// Finds an agent CLI. A Mac app does not get the shell's PATH, so the usual install places are searched too.
public enum AgentLocator {
    public static var searchDirectories: [String] {
        let home = NSHomeDirectory()
        let inherited = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        return inherited + [
            "/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin", "\(home)/.claude/local",
            "\(home)/.npm-global/bin", "\(home)/.bun/bin", "\(home)/.opencode/bin", "\(home)/.cargo/bin",
        ]
    }

    /// A PATH value to give to agent processes, so tools such as `node` are found.
    public static var environmentPATH: String {
        var seen = Set<String>()
        return (searchDirectories + ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]).filter { seen.insert($0).inserted }.joined(separator: ":")
    }

    public static func find(_ kind: AgentKind, extraDirectories: [String] = []) -> URL? {
        for directory in extraDirectories + searchDirectories {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent(kind.executableName)
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    public static func installed() -> [AgentKind] {
        AgentKind.allCases.filter { $0.isEnabled && find($0) != nil }
    }
}

/// One run of an agent in a scene folder.
public final class AgentSession: @unchecked Sendable {
    public let events: AsyncStream<AgentEvent>
    private let continuation: AsyncStream<AgentEvent>.Continuation
    private let process = Process()
    private let kind: AgentKind
    private let lock = NSLock()
    private var buffer = Data()
    private var errorOutput = Data()
    private var sawResult = false
    private var cancelled = false

    public init(kind: AgentKind, executable: URL, request: AgentRequest, sceneDirectory: URL, model: String? = nil, effort: String? = nil) {
        self.kind = kind
        var continuation: AsyncStream<AgentEvent>.Continuation!
        events = AsyncStream { continuation = $0 }
        self.continuation = continuation

        process.executableURL = executable
        process.currentDirectoryURL = sceneDirectory
        process.arguments = kind.arguments(prompt: request.prompt(sceneDirectory: sceneDirectory),
                                           imagePaths: request.imagePaths(sceneDirectory: sceneDirectory),
                                           splashCLI: request.splashCLI, model: model, effort: effort)
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = AgentLocator.environmentPATH
        process.environment = environment
        // Agents in print mode must never wait for input.
        process.standardInput = FileHandle.nullDevice
    }

    public func start() {
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.consume(data)
        }
        errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let self else { return }
            self.lock.lock(); self.errorOutput.append(data); self.lock.unlock()
        }
        process.terminationHandler = { [weak self] finished in
            output.fileHandleForReading.readabilityHandler = nil
            errors.fileHandleForReading.readabilityHandler = nil
            self?.finish(status: finished.terminationStatus)
        }
        do {
            try process.run()
        } catch {
            continuation.yield(.failed("Could not start \(kind.displayName): \(error.localizedDescription)"))
            continuation.finish()
        }
    }

    public func cancel() {
        lock.lock(); cancelled = true; lock.unlock()
        if process.isRunning { process.terminate() }
    }

    private func consume(_ data: Data) {
        lock.lock()
        buffer.append(data)
        var lines: [String] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            lines.append(String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self))
            buffer.removeSubrange(buffer.startIndex...newline)
        }
        lock.unlock()
        emit(lines)
    }

    private func emit(_ lines: [String]) {
        for line in lines {
            for event in AgentOutputParser.parse(line: line, kind: kind) {
                if case .finished = event {
                    lock.lock(); sawResult = true; lock.unlock()
                }
                continuation.yield(event)
            }
        }
    }

    private func finish(status: Int32) {
        lock.lock()
        let remainder = String(decoding: buffer, as: UTF8.self)
        buffer.removeAll()
        let errorText = String(decoding: errorOutput, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let wasCancelled = cancelled
        let alreadyFinished = sawResult
        lock.unlock()

        emit([remainder])
        if wasCancelled {
            continuation.yield(.failed("Stopped."))
        } else if status != 0 {
            continuation.yield(.failed(errorText.isEmpty ? "\(kind.displayName) exited with status \(status)." : String(errorText.suffix(600))))
        } else if !alreadyFinished {
            continuation.yield(.finished(success: true))
        }
        continuation.finish()
    }
}

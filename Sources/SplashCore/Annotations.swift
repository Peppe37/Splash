import Foundation

/// A comment pinned to a point of the preview.
public struct Comment: Codable, Equatable, Sendable {
    /// Position as a fraction of the frame: 0 is left or top, 1 is right or bottom.
    public var x: Double
    public var y: Double
    /// `splash.time` when the comment was made.
    public var time: Double?
    public var text: String

    public init(x: Double, y: Double, time: Double? = nil, text: String) {
        self.x = x
        self.y = y
        self.time = time
        self.text = text
    }
}

/// Everything the user sends to an agent in one turn.
public struct AgentRequest: Sendable {
    public var text: String
    /// The preview frame with the user's drawings, as a PNG inside the scene folder.
    public var annotatedImage: URL?
    public var comments: [Comment]
    /// Full path of the `splash` tool, so the agent can lint without it being on the PATH.
    public var splashCLI: String?

    public init(text: String, annotatedImage: URL? = nil, comments: [Comment] = [], splashCLI: String? = nil) {
        self.text = text
        self.annotatedImage = annotatedImage
        self.comments = comments
        self.splashCLI = splashCLI
    }

    /// The text sent to the agent.
    public func prompt(sceneDirectory: URL) -> String {
        var lines = [
            "You are editing a Splash animated wallpaper scene in the current working directory. Read AGENTS.md first and follow its rules.",
            "Only read and change files inside the current working directory. Never touch anything outside it.",
            "",
            "Request: \(text)",
        ]
        if let annotatedImage {
            let relative = annotatedImage.path.replacingOccurrences(of: sceneDirectory.path + "/", with: "")
            lines += ["", "The file \(relative) is a frame of the current scene with the user's drawings on top. Look at it."]
        }
        if !comments.isEmpty {
            lines += ["", "Numbered pins in that image carry these comments (x and y are fractions of the frame, from the top left):"]
            for (index, comment) in comments.enumerated() {
                var line = "\(index + 1). at (\(Self.format(comment.x)), \(Self.format(comment.y)))"
                if let time = comment.time { line += ", at \(Self.format(time)) s" }
                lines.append(line + ": \(comment.text)")
            }
            lines.append("Change only what the drawings and comments point at.")
        }
        if let splashCLI {
            lines += ["", "When you are done, run `\(splashCLI) lint .` and fix every error."]
        } else {
            lines += ["", "When you are done, run `splash lint .` if it is available and fix every error."]
        }
        lines += ["Finish with one or two sentences saying what you changed."]
        return lines.joined(separator: "\n")
    }

    static func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

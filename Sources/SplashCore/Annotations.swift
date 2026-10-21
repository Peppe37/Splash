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

/// A file the user gave to the agent: a picture to put in the scene, a reference to look at, a video.
public struct AttachedFile: Equatable, Sendable {
    public enum Role: String, Sendable {
        /// Copied into the scene's `assets` folder: the scene can use it (a character, a logo, a texture).
        case use
        /// Kept out of the scene, in `.splash/references`: only for the agent to look at.
        case reference
    }

    public enum Kind: String, Sendable {
        case image, svg, video, model, other

        public static func detect(extension ext: String) -> Kind {
            switch ext.lowercased() {
            case "png", "jpg", "jpeg", "gif", "webp", "heic", "avif", "tiff", "bmp": return .image
            case "svg": return .svg
            case "mp4", "mov", "m4v", "webm": return .video
            case "glb", "gltf", "obj", "usdz", "stl": return .model
            default: return .other
            }
        }

        var description: String {
            switch self {
            case .image: return "an image"
            case .svg: return "an SVG drawing"
            case .video: return "a video"
            case .model: return "a 3D model"
            case .other: return "a file"
            }
        }
    }

    /// Path inside the scene folder, such as `assets/hero.svg`.
    public var path: String
    public var role: Role
    public var kind: Kind
    /// For a video: pictures taken from it, inside the scene folder, which the agent can look at.
    public var frames: [String]

    public init(path: String, role: Role, kind: Kind, frames: [String] = []) {
        self.path = path
        self.role = role
        self.kind = kind
        self.frames = frames
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
    public var attachments: [AttachedFile]

    public init(text: String, annotatedImage: URL? = nil, comments: [Comment] = [], splashCLI: String? = nil, attachments: [AttachedFile] = []) {
        self.text = text
        self.annotatedImage = annotatedImage
        self.comments = comments
        self.splashCLI = splashCLI
        self.attachments = attachments
    }

    /// Pictures to hand to the agent as images: the annotated frame, image attachments and the frames of videos.
    public func imagePaths(sceneDirectory: URL) -> [String] {
        var paths: [String] = []
        if let annotatedImage { paths.append(annotatedImage.path) }
        for file in attachments {
            if file.kind == .image { paths.append(sceneDirectory.appendingPathComponent(file.path).path) }
            paths += file.frames.map { sceneDirectory.appendingPathComponent($0).path }
        }
        return paths
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
        let toUse = attachments.filter { $0.role == .use }, references = attachments.filter { $0.role == .reference }
        if !toUse.isEmpty {
            lines += ["", "The user gave you files to use in the scene. They are already in the scene folder. Load each file itself with its relative path (an <img>, or an Image drawn on the canvas): do not redraw its shapes by hand, and do not move it."]
            lines += toUse.map { "- \($0.path): \($0.kind.description)" + Self.frameNote($0) }
        }
        if !references.isEmpty {
            lines += ["", "The user gave you files as references. Look at them to understand what they want, but do not use them in the scene:"]
            lines += references.map { "- \($0.path): \($0.kind.description)" + Self.frameNote($0) }
        }
        if let splashCLI {
            lines += ["", "When you are done, run `\(splashCLI) lint .` and fix every error."]
        } else {
            lines += ["", "When you are done, run `splash lint .` if it is available and fix every error."]
        }
        lines += ["Finish with one or two sentences saying what you changed."]
        return lines.joined(separator: "\n")
    }

    static func frameNote(_ file: AttachedFile) -> String {
        file.frames.isEmpty ? "" : ". You cannot play it: look at these pictures taken from it instead: " + file.frames.joined(separator: ", ")
    }

    static func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

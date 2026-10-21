import Foundation

/// How a scene ends up on the desktop, from the lightest to the heaviest.
public enum ApplyTier: String, Codable, CaseIterable, Sendable {
    /// One image set as the real macOS wallpaper. No process runs.
    case `static`
    /// A looping HEVC video played with hardware decoding.
    case baked
    /// Drawn in real time (WebGL or Metal). Only for scenes that cannot be baked.
    case live
}

public enum SceneRuntime: String, Codable, Sendable {
    /// HTML, CSS and JavaScript shown in a WKWebView.
    case web
    /// A Metal shader drawn by the runner, without a web process.
    case metal
}

public struct ScenePermissions: Codable, Equatable, Sendable {
    public var network: Bool
    public var audio: Bool
    public var location: Bool

    public init(network: Bool = false, audio: Bool = false, location: Bool = false) {
        self.network = network
        self.audio = audio
        self.location = location
    }

    enum CodingKeys: String, CodingKey { case network, audio, location }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        network = try container.decodeIfPresent(Bool.self, forKey: .network) ?? false
        audio = try container.decodeIfPresent(Bool.self, forKey: .audio) ?? false
        location = try container.decodeIfPresent(Bool.self, forKey: .location) ?? false
    }
}

public enum ParamType: String, Codable, Sendable {
    case number, color, bool, choice
}

/// One adjustable value of a scene. The editor builds its controls from this list.
public struct SceneParam: Codable, Equatable, Sendable {
    public var key: String
    public var label: String
    public var type: ParamType
    public var `default`: JSONValue
    public var min: Double?
    public var max: Double?
    public var step: Double?
    public var options: [String]?

    public init(key: String, label: String, type: ParamType, default value: JSONValue,
                min: Double? = nil, max: Double? = nil, step: Double? = nil, options: [String]? = nil) {
        self.key = key
        self.label = label
        self.type = type
        self.default = value
        self.min = min
        self.max = max
        self.step = step
        self.options = options
    }
}

/// The content of `scene.json`.
public struct SceneManifest: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var id: String
    public var name: String
    public var author: String?
    public var description: String?
    public var runtime: SceneRuntime
    /// Main file of the scene, relative to its folder.
    public var entry: String
    /// Tiers the scene can be applied with. The first one is the preferred one.
    public var tiers: [ApplyTier]
    /// Frame rate cap while the scene is live.
    public var fps: Int
    /// Length of one loop in seconds. Needed to bake the scene.
    public var loopSeconds: Double?
    public var permissions: ScenePermissions
    public var params: [SceneParam]

    public init(schemaVersion: Int = SceneManifest.currentSchemaVersion, id: String, name: String,
                author: String? = nil, description: String? = nil, runtime: SceneRuntime = .web,
                entry: String = "index.html", tiers: [ApplyTier] = [.baked, .live], fps: Int = 30,
                loopSeconds: Double? = nil, permissions: ScenePermissions = ScenePermissions(),
                params: [SceneParam] = []) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.author = author
        self.description = description
        self.runtime = runtime
        self.entry = entry
        self.tiers = tiers
        self.fps = fps
        self.loopSeconds = loopSeconds
        self.permissions = permissions
        self.params = params
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion, id, name, author, description, runtime, entry, tiers, fps, loopSeconds, permissions, params
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.currentSchemaVersion
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        author = try container.decodeIfPresent(String.self, forKey: .author)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        runtime = try container.decodeIfPresent(SceneRuntime.self, forKey: .runtime) ?? .web
        entry = try container.decodeIfPresent(String.self, forKey: .entry) ?? "index.html"
        tiers = try container.decodeIfPresent([ApplyTier].self, forKey: .tiers) ?? [.baked, .live]
        fps = try container.decodeIfPresent(Int.self, forKey: .fps) ?? 30
        loopSeconds = try container.decodeIfPresent(Double.self, forKey: .loopSeconds)
        permissions = try container.decodeIfPresent(ScenePermissions.self, forKey: .permissions) ?? ScenePermissions()
        params = try container.decodeIfPresent([SceneParam].self, forKey: .params) ?? []
    }

    /// The tier to use when the user does not choose one.
    public var preferredTier: ApplyTier { tiers.first ?? .live }

    /// The moment shown in thumbnails and in the still picture under a moving wallpaper: a quarter of the way through the loop.
    public var stillTime: Double { (loopSeconds ?? 0) * 0.25 }
}

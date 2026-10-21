import Foundation

/// Choices about how Splash sets the real macOS wallpaper. Saved in the same defaults as the power settings.
public struct DesktopSettings: Equatable, Sendable {
    /// Put the picture on every Space and display, not only the one on screen. This edits macOS's wallpaper settings file
    /// (the original is saved first and can be put back).
    public var applyToAllSpaces: Bool

    public init(applyToAllSpaces: Bool = true) {
        self.applyToAllSpaces = applyToAllSpaces
    }

    public static func load() -> DesktopSettings {
        let defaults = UserDefaults(suiteName: PowerSettings.defaultsSuite)
        return DesktopSettings(applyToAllSpaces: defaults?.object(forKey: "applyToAllSpaces") as? Bool ?? true)
    }

    public func save() {
        UserDefaults(suiteName: PowerSettings.defaultsSuite)?.set(applyToAllSpaces, forKey: "applyToAllSpaces")
    }
}

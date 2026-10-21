import Foundation

/// What the Mac is doing right now, as far as the wallpaper cares.
public struct SystemState: Equatable, Sendable {
    public enum Thermal: Int, Comparable, Sendable {
        case nominal, fair, serious, critical
        public static func < (lhs: Thermal, rhs: Thermal) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public var onBattery: Bool
    public var lowPowerMode: Bool
    public var thermal: Thermal
    /// The wallpaper window is fully covered by other windows.
    public var occluded: Bool
    public var screenAsleep: Bool
    public var screenLocked: Bool
    /// The user chose Pause in the menu.
    public var userPaused: Bool

    public init(onBattery: Bool = false, lowPowerMode: Bool = false, thermal: Thermal = .nominal,
                occluded: Bool = false, screenAsleep: Bool = false, screenLocked: Bool = false, userPaused: Bool = false) {
        self.onBattery = onBattery
        self.lowPowerMode = lowPowerMode
        self.thermal = thermal
        self.occluded = occluded
        self.screenAsleep = screenAsleep
        self.screenLocked = screenLocked
        self.userPaused = userPaused
    }
}

/// User choices about power use. The defaults favour the battery.
public struct PowerSettings: Equatable, Sendable {
    public var pauseOnBattery: Bool
    public var pauseInLowPowerMode: Bool
    public var batteryFPSCap: Int

    public init(pauseOnBattery: Bool = false, pauseInLowPowerMode: Bool = true, batteryFPSCap: Int = 15) {
        self.pauseOnBattery = pauseOnBattery
        self.pauseInLowPowerMode = pauseInLowPowerMode
        self.batteryFPSCap = batteryFPSCap
    }

    /// The defaults domain shared by the editor (which writes the settings) and the runner (which reads them).
    public static let defaultsSuite = "com.giuseppe.splash"

    /// Reads the saved choices. Anything not saved keeps its default.
    public init(defaults: UserDefaults?) {
        let base = PowerSettings()
        pauseOnBattery = defaults?.object(forKey: "pauseOnBattery") as? Bool ?? base.pauseOnBattery
        pauseInLowPowerMode = defaults?.object(forKey: "pauseInLowPowerMode") as? Bool ?? base.pauseInLowPowerMode
        let cap = defaults?.object(forKey: "batteryFPSCap") as? Int ?? base.batteryFPSCap
        batteryFPSCap = min(max(cap, 1), 60)
    }

    public static func load() -> PowerSettings {
        PowerSettings(defaults: UserDefaults(suiteName: defaultsSuite))
    }

    public func save() {
        let defaults = UserDefaults(suiteName: Self.defaultsSuite)
        defaults?.set(pauseOnBattery, forKey: "pauseOnBattery")
        defaults?.set(pauseInLowPowerMode, forKey: "pauseInLowPowerMode")
        defaults?.set(batteryFPSCap, forKey: "batteryFPSCap")
    }
}

public enum RenderDecision: Equatable, Sendable {
    /// Draw at this frame rate.
    case run(fps: Int)
    /// Keep the scene but stop drawing (short pauses, cheap to resume).
    case pause
    /// Destroy the renderer and free its memory (long pauses). Resume rebuilds it.
    case suspend
}

/// The single place that decides how much work the wallpaper may do. Pure, so every rule has a test.
public enum PerformancePolicy {
    public static func decide(sceneFPS: Int, state: SystemState, settings: PowerSettings = PowerSettings()) -> RenderDecision {
        if state.screenAsleep || state.screenLocked { return .suspend }
        if state.occluded { return .suspend }
        if state.userPaused { return .pause }
        if state.thermal >= .serious { return .pause }
        if state.lowPowerMode && settings.pauseInLowPowerMode { return .pause }
        if state.onBattery && settings.pauseOnBattery { return .pause }

        var fps = max(1, min(sceneFPS, 60))
        if state.onBattery || state.lowPowerMode { fps = min(fps, settings.batteryFPSCap) }
        if state.thermal == .fair { fps = min(fps, 24) }
        return .run(fps: fps)
    }
}

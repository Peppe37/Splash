import AppKit
import SplashCore
import IOKit.ps

/// Watches the few system signals that matter and reports a `SystemState`.
/// Everything here is event-driven: no timers, no polling, so an idle wallpaper costs nothing.
@MainActor
final class SystemMonitor {
    private(set) var state = SystemState()
    var onChange: ((SystemState) -> Void)?

    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var powerSource: CFRunLoopSource?

    func start() {
        let defaultCenter = NotificationCenter.default
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let lock = DistributedNotificationCenter.default()

        observe(defaultCenter, ProcessInfo.thermalStateDidChangeNotification) { $0.refreshProcessState() }
        observe(defaultCenter, .NSProcessInfoPowerStateDidChange) { $0.refreshProcessState() }
        observe(workspaceCenter, NSWorkspace.screensDidSleepNotification) { $0.update { $0.screenAsleep = true } }
        observe(workspaceCenter, NSWorkspace.screensDidWakeNotification) { $0.update { $0.screenAsleep = false } }
        observe(lock, Notification.Name("com.apple.screenIsLocked")) { $0.update { $0.screenLocked = true } }
        observe(lock, Notification.Name("com.apple.screenIsUnlocked")) { $0.update { $0.screenLocked = false } }

        // Fires only when the power source changes (plug, unplug), never on a schedule.
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<SystemMonitor>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in monitor.refreshProcessState() }
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            powerSource = source
        }
        refreshProcessState()
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ handler: @escaping @MainActor (SystemMonitor) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if let self { handler(self) } }
        }
        observers.append((center, token))
    }

    private func refreshProcessState() {
        let info = ProcessInfo.processInfo
        update {
            $0.lowPowerMode = info.isLowPowerModeEnabled
            $0.thermal = SystemState.Thermal(rawValue: info.thermalState.rawValue) ?? .nominal
            $0.onBattery = Self.isOnBattery()
        }
    }

    private func update(_ change: (inout SystemState) -> Void) {
        var next = state
        change(&next)
        guard next != state else { return }
        state = next
        onChange?(next)
    }

    private static func isOnBattery() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? else { return false }
        return type == kIOPSBatteryPowerValue
    }
}

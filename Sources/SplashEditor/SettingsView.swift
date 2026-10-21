import SplashCore
import SwiftUI

/// Power choices for the wallpaper. They are saved in the shared defaults and the runner reads them when told.
struct SettingsView: View {
    @State private var settings = PowerSettings.load()

    var body: some View {
        Form {
            Section("Power") {
                Toggle("Pause on battery", isOn: $settings.pauseOnBattery)
                Toggle("Pause in Low Power Mode", isOn: $settings.pauseInLowPowerMode)
                Stepper("Frame rate on battery: \(settings.batteryFPSCap) fps", value: $settings.batteryFPSCap, in: 5...30, step: 5)
            }
            Section {
                Text("The wallpaper always stops drawing when it is covered, when the screen sleeps or locks, and when the Mac gets hot. A paused wallpaper shows a still picture.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 260)
        .onChange(of: settings) { _, new in
            new.save()
            RunnerMessage.post(RunnerMessage.settings)
        }
    }
}

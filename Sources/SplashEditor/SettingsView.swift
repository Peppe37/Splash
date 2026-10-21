import AppKit
import SplashCore
import SwiftUI

/// Settings: power choices for the wallpaper, and an About page with the version, links, a way to review and support the project.
struct SettingsView: View {
    var body: some View {
        TabView {
            PowerSettingsView()
                .tabItem { Label("Power", systemImage: "bolt") }
            AboutView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 470)
    }
}

/// Power choices for the wallpaper. They are saved in the shared defaults and the runner reads them when told.
struct PowerSettingsView: View {
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
        .onChange(of: settings) { _, new in
            new.save()
            RunnerMessage.post(RunnerMessage.settings)
        }
    }
}

enum Project {
    static let repo = "https://github.com/Peppe37/Splash"
    static let site = "https://peppe37.github.io/Splash/"
    /// Every release so far is an alpha, like Notcholino's: versions look like 0.1.0-alpha.
    static let channel = "alpha"

    /// The version of this build. A build made with `swift build` has no bundle, so it says "dev".
    static var version: String {
        guard let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else { return "dev" }
        return channel.isEmpty ? short : "\(short)-\(channel)"
    }
}

struct AboutView: View {
    private let updates = UpdateChecker.shared
    private let installer = AppUpdater.shared
    @State private var checkForUpdates = UpdateChecker.shared.isEnabled

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Splash").font(.title2.weight(.semibold))
                        Text("Version \(Project.version)").foregroundStyle(.secondary)
                        Text("Free and open source, GPL-3.0").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                if let release = updates.available {
                    LabeledContent("Update") {
                        HStack {
                            Link("Version \(release.version) is available", destination: release.url)
                            Button(installer.status ?? "Update and restart") { installer.install(release) }
                                .disabled(installer.isWorking)
                        }
                    }
                    if let failure = installer.failure {
                        Text(failure).font(.caption).foregroundStyle(.orange)
                    }
                } else if checkForUpdates {
                    LabeledContent("Update", value: updates.couldNotCheck ? "Could not check" : (updates.lastChecked == nil ? "Not checked yet" : "You have the latest version"))
                }
                Toggle("Check for new versions", isOn: $checkForUpdates)
                    .onChange(of: checkForUpdates) { _, value in updates.isEnabled = value }
                Button(updates.isChecking ? "Checking…" : "Check now") { Task { await updates.check() } }
                    .disabled(updates.isChecking)
            } header: {
                Text("Updates")
            } footer: {
                Text("Once a day, while Splash is open, it asks GitHub for the list of releases (a single small request) and tells you when there is a newer one. The wallpaper itself never uses the network. It never downloads or installs anything by itself: Update and restart does it when you press it, keeping your permissions.")
            }

            Section("Feedback") {
                link("Website", Project.site)
                link("Source code", Project.repo)
                link("Report a bug", "\(Project.repo)/issues/new?template=bug_report.yml")
                link("Write a review", "\(Project.repo)/issues/new?template=review.yml&version=\(Project.version)")
                link("Ask a question or share an idea", "\(Project.repo)/discussions")
            }

            Section("Support the project") {
                Text("Splash is free and made by one person. If it is useful to you, you can help keep it going.")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    supportButton("GitHub Sponsors", "https://github.com/sponsors/Peppe37")
                    supportButton("Ko-fi", "https://ko-fi.com/giuseppelapietra")
                    supportButton("Buy Me a Coffee", "https://www.buymeacoffee.com/giuseppelapietra")
                }
            }
        }
        .formStyle(.grouped)
    }

    private func link(_ title: String, _ url: String) -> some View {
        Button { if let url = URL(string: url) { NSWorkspace.shared.open(url) } } label: {
            HStack { Text(title); Spacer(); Image(systemName: "arrow.up.right").foregroundStyle(.secondary) }
        }
        .buttonStyle(.plain)
    }

    private func supportButton(_ title: String, _ url: String) -> some View {
        Button(title) { if let url = URL(string: url) { NSWorkspace.shared.open(url) } }
    }
}

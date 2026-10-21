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
    @State private var check: UpdateCheck.State = .idle

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

            Section("Updates") {
                updateRow
                Text("Splash only talks to GitHub when you press this. It never downloads or installs anything by itself.")
                    .font(.caption).foregroundStyle(.secondary)
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

    @ViewBuilder private var updateRow: some View {
        switch check {
        case .idle:
            Button("Check for updates") { run() }
        case .checking:
            HStack { ProgressView().controlSize(.small); Text("Checking…") }
        case .upToDate:
            HStack { Label("You are up to date", systemImage: "checkmark.circle.fill").foregroundStyle(.green); Spacer(); Button("Check again") { run() } }
        case .available(let tag, let url):
            HStack {
                Label("\(tag) is available", systemImage: "arrow.down.circle.fill")
                Spacer()
                Button("Download") { NSWorkspace.shared.open(url) }
            }
        case .failed(let message):
            HStack { Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange); Spacer(); Button("Try again") { run() } }
        }
    }

    private func run() {
        check = .checking
        Task { check = await UpdateCheck.run(current: Project.version) }
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

/// Asks GitHub for the list of releases, once, when the user asks. Nothing is downloaded.
enum UpdateCheck {
    enum State: Equatable {
        case idle, checking, upToDate
        case available(String, URL)
        case failed(String)
    }

    static func run(current: String) async -> State {
        guard let url = URL(string: "https://api.github.com/repos/Peppe37/Splash/releases?per_page=30") else { return .failed("Bad address") }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return .failed("GitHub did not answer") }
            let releases = try JSONDecoder().decode([Release].self, from: data)
            // App releases are tagged v<version>; drafts are skipped.
            guard let latest = releases.first(where: { !$0.draft && $0.tag_name.range(of: #"^v\d"#, options: .regularExpression) != nil }) else {
                return .upToDate
            }
            let latestVersion = String(latest.tag_name.dropFirst())
            guard VersionOrder.isNewer(latestVersion, than: current), let page = URL(string: latest.html_url) else { return .upToDate }
            return .available(latest.tag_name, page)
        } catch {
            return .failed("Could not check")
        }
    }

    struct Release: Decodable {
        let tag_name: String
        let html_url: String
        let draft: Bool
    }
}

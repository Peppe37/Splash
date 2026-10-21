import AppKit
import SplashCore
import SwiftUI

enum InspectorTab: String, CaseIterable, Identifiable {
    case parameters = "Controls"
    case versions = "Versions"
    case details = "Details"
    var id: String { rawValue }
}

struct Inspector: View {
    let scene: WallpaperScene
    @State private var tab: InspectorTab = .parameters

    var body: some View {
        VStack(spacing: 0) {
            TabRow(values: InspectorTab.allCases, selection: $tab, title: \.rawValue)
            Hairline()
            ScrollView {
                Group {
                    switch tab {
                    case .parameters: ControlsTab(scene: scene)
                    case .versions: VersionsTab()
                    case .details: DetailsTab(scene: scene)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)
        }
    }
}

// MARK: - Controls

struct ControlsTab: View {
    @Environment(AppModel.self) private var model
    let scene: WallpaperScene

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if scene.manifest.params.isEmpty {
                Text("This scene has nothing to adjust. Ask the AI to add controls, or edit scene.json.")
                    .font(.system(size: 13)).foregroundStyle(Theme.muted).lineSpacing(2)
            } else {
                ForEach(scene.manifest.params, id: \.key) { param in control(for: param) }
                Hairline()
                HStack {
                    Button("Reset") { model.resetValues() }.buttonStyle(.splash)
                    Spacer()
                }
                if model.isAppliedSceneSelected, let tier = model.applied?.tier, tier != .live {
                    Text("This wallpaper is a \(TopBar.tierName(tier)). Press Apply again to use new values.")
                        .font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
            }
        }
    }

    @ViewBuilder private func control(for param: SceneParam) -> some View {
        switch param.type {
        case .number:
            let range = (param.min ?? 0)...(param.max ?? 1)
            let binding = Binding<Double>(
                get: { model.values[param.key]?.number ?? param.default.number ?? 0 },
                set: { model.setValue(param.key, to: .number($0)) })
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(param.label).font(.system(size: 13))
                    Spacer()
                    Text(binding.wrappedValue.formatted(.number.precision(.fractionLength(0...2))))
                        .font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.muted)
                }
                Group {
                    if let step = param.step { Slider(value: binding, in: range, step: step) } else { Slider(value: binding, in: range) }
                }
                .tint(Theme.strong)
                .controlSize(.small)
            }
        case .color:
            let binding = Binding<Color>(
                get: { Color(hex: model.values[param.key]?.string ?? param.default.string ?? "#000000") },
                set: { model.setValue(param.key, to: .string($0.hexString)) })
            HStack {
                Text(param.label).font(.system(size: 13))
                Spacer()
                Text((model.values[param.key]?.string ?? "").uppercased())
                    .font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.muted)
                ColorPicker("", selection: binding, supportsOpacity: false).labelsHidden()
            }
        case .bool:
            Toggle(isOn: Binding(
                get: { model.values[param.key]?.bool ?? param.default.bool ?? false },
                set: { model.setValue(param.key, to: .bool($0)) })) {
                Text(param.label).font(.system(size: 13))
            }
            .toggleStyle(.switch).controlSize(.small)
        case .choice:
            HStack {
                Text(param.label).font(.system(size: 13))
                Spacer()
                Picker("", selection: Binding(
                    get: { model.values[param.key]?.string ?? param.default.string ?? "" },
                    set: { model.setValue(param.key, to: .string($0)) })) {
                    ForEach(param.options ?? [], id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden().fixedSize()
            }
        }
    }
}

extension Color {
    init(hex: String) {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: digits).scanHexInt64(&value)
        self.init(.sRGB, red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }

    var hexString: String {
        let color = NSColor(self).usingColorSpace(.sRGB) ?? .black
        return String(format: "#%02x%02x%02x", Int((color.redComponent * 255).rounded()), Int((color.greenComponent * 255).rounded()), Int((color.blueComponent * 255).rounded()))
    }
}

// MARK: - Versions

struct VersionsTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("A version is saved before every AI change, so you can always go back.")
                .font(.system(size: 13)).foregroundStyle(Theme.muted).lineSpacing(2)
            Button("Save a version") { model.takeSnapshot(label: "Saved by hand") }.buttonStyle(.splash)
            if !model.history.isEmpty {
                VStack(spacing: 0) {
                    ForEach(model.history) { entry in
                        VStack(spacing: 0) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(entry.label).font(.system(size: 13)).lineLimit(2)
                                    Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.muted)
                                }
                                Spacer()
                                Button("Restore") { model.restore(entry) }.buttonStyle(.splashGhost)
                            }
                            .padding(.vertical, 10)
                            Hairline()
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Details

struct DetailsTab: View {
    @Environment(AppModel.self) private var model
    let scene: WallpaperScene

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Scene")
                row("Name", scene.manifest.name)
                if let about = scene.manifest.description { row("About", about) }
                row("Ways to apply", scene.manifest.tiers.map(TopBar.tierName).joined(separator: ", "))
                row("Frame rate", "\(scene.manifest.fps) fps")
                if let loop = scene.manifest.loopSeconds { row("Loop", "\(Int(loop)) s") }
            }
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Allowed to")
                row("Use the network", scene.manifest.permissions.network ? "yes" : "no")
                row("Listen to audio", scene.manifest.permissions.audio ? "yes" : "no")
            }
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Checks")
                if model.issues.isEmpty {
                    Badge(text: "No problems", tint: Theme.green)
                } else {
                    ForEach(Array(model.issues.enumerated()), id: \.offset) { _, issue in
                        HStack(alignment: .top, spacing: 8) {
                            Badge(text: issue.severity == .error ? "error" : "warning", tint: issue.severity == .error ? Theme.red : Theme.purple)
                            Text(issue.message).font(.system(size: 12)).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            Button("Show in Finder") { model.revealSelected() }.buttonStyle(.splash)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).font(.system(size: 13)).foregroundStyle(Theme.muted)
            Spacer(minLength: 12)
            Text(value).font(.system(size: 13)).multilineTextAlignment(.trailing)
        }
    }
}

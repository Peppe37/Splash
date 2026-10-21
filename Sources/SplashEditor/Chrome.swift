import SplashCore
import SwiftUI

/// The window: a top bar, and either the library or the editor of one scene.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.bg
            VStack(spacing: 0) {
                TopBar()
                Hairline()
                if let scene = model.selected {
                    EditorView(scene: scene).id(scene.manifest.id)
                } else {
                    LibraryView()
                }
            }
            ToastHost()
        }
        .ignoresSafeArea()
        .background(WindowChrome())
        .foregroundStyle(Theme.text)
    }
}

struct TopBar: View {
    @Environment(AppModel.self) private var model
    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmingDelete = false

    var body: some View {
        HStack(spacing: 10) {
            if let scene = model.selected {
                editorBar(scene)
            } else {
                libraryBar
            }
        }
        // Room for the window's traffic lights.
        .padding(.leading, 84)
        .padding(.trailing, 16)
        .frame(height: 52)
    }

    private var libraryBar: some View {
        HStack {
            Text("Splash")
                .font(.system(size: 15, weight: .medium))
                .tracking(-0.2)
                .foregroundStyle(Theme.strong)
            Spacer()
            if let release = UpdateChecker.shared.available {
                Button { NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) } label: {
                    Label("Update \(release.version)", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.splash)
                .help("A new version is available. Open Settings → About to install it.")
            }
            Menu {
                ForEach(Presets.all, id: \.id) { preset in
                    Button(preset.name) { model.create(from: preset) }
                }
            } label: {
                Label("New scene", systemImage: "plus")
            }
            .menuStyle(.button)
            .buttonStyle(.splashPrimary)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    @ViewBuilder
    private func editorBar(_ scene: WallpaperScene) -> some View {
        Button { model.select(nil) } label: {
            Label("Library", systemImage: "chevron.left")
        }
        .buttonStyle(.splashGhost)

        Hairline(vertical: true).frame(height: 16)

        Text(scene.manifest.name)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Theme.strong)
            .lineLimit(1)

        if model.isAppliedSceneSelected, let applied = model.applied {
            Badge(text: "On desktop · \(Self.tierName(applied.tier))", tint: Theme.green)
        }

        Spacer()

        TierPicker(scene: scene)

        applyButton

        Menu {
            Button("Rename…") { newName = scene.manifest.name; renaming = true }
            Button("Duplicate") { model.duplicateSelected() }
            Button("Show in Finder") { model.revealSelected() }
            Divider()
            if model.isAppliedSceneSelected, model.applied?.tier != .static {
                Button("Stop wallpaper") { model.stopWallpaper() }
            }
            if model.canRestoreWallpaper {
                Button("Put back my previous wallpaper") { model.restorePreviousWallpaper() }
            }
            Divider()
            Button("Delete scene…", role: .destructive) { confirmingDelete = true }
        } label: {
            Image(systemName: "ellipsis")
        }
        .menuStyle(.button)
        .buttonStyle(IconButtonStyle())
        .menuIndicator(.hidden)
        .fixedSize()
        .alert("Rename scene", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Rename") { model.rename(scene, to: newName) }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete \"\(scene.manifest.name)\"?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) { model.delete(scene) }
        } message: {
            Text("The scene's folder and its versions are removed. This cannot be undone.")
        }
    }

    @ViewBuilder private var applyButton: some View {
        if case .working(let text, let progress) = model.applyState {
            HStack(spacing: 8) {
                ProgressView(value: progress).progressViewStyle(.linear).frame(width: 90)
                Text(progress.map { "\(text.replacingOccurrences(of: "…", with: "")) \(Int($0 * 100))%" } ?? text)
                    .font(.system(size: 12)).foregroundStyle(Theme.muted).monospacedDigit()
                Button("Cancel") { model.cancelApply() }.buttonStyle(.splashGhost)
            }
        } else {
            Button { model.apply(model.chosenTier) } label: { Text("Apply") }
                .buttonStyle(.splashPrimary)
                .keyboardShortcut(.return, modifiers: .command)
                .help("Put this scene on your desktop (⌘↩)")
        }
    }

    static func tierName(_ tier: ApplyTier) -> String {
        switch tier {
        case .static: return "still"
        case .baked: return "loop"
        case .live: return "live"
        }
    }
}

/// Still, Loop or Live: how the scene will be put on the desktop. Only the ways the scene supports are shown.
struct TierPicker: View {
    @Environment(AppModel.self) private var model
    let scene: WallpaperScene

    var body: some View {
        let tiers = ApplyTier.allCases.filter { scene.manifest.tiers.contains($0) }
        if tiers.count > 1 {
            HStack(spacing: 0) {
                ForEach(tiers, id: \.self) { tier in
                    Button { model.chosenTier = tier } label: {
                        Text(label(tier))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(model.chosenTier == tier ? Theme.strong : Theme.muted)
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .background(model.chosenTier == tier ? Theme.surfaceRaised : .clear, in: RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    .help(help(tier))
                }
            }
            .padding(2)
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control).stroke(Theme.border))
        } else if let only = tiers.first {
            Badge(text: label(only))
        }
    }

    private func label(_ tier: ApplyTier) -> String {
        switch tier {
        case .static: return "Still"
        case .baked: return "Loop"
        case .live: return "Live"
        }
    }

    private func help(_ tier: ApplyTier) -> String {
        switch tier {
        case .static: return "One picture set as your wallpaper. Nothing runs. Lightest."
        case .baked: return "A recorded loop played by the system's video decoder. Very light."
        case .live: return "Drawn in real time. Needed for scenes that react to something. Heaviest."
        }
    }
}

/// A short message at the bottom of the window. It goes away by itself.
struct ToastHost: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack {
            if let banner = model.banner {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: banner.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(banner.isError ? Theme.red : Theme.green)
                    Text(banner.text)
                        .font(.system(size: 13))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Button { model.banner = nil } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.muted)
                }
                .padding(12)
                .frame(maxWidth: 520, alignment: .leading)
                .panel(radius: Theme.Radius.card)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: banner) {
                    try? await Task.sleep(nanoseconds: banner.isError ? 12_000_000_000 : 6_000_000_000)
                    if model.banner == banner { withAnimation(.easeOut(duration: 0.2)) { model.banner = nil } }
                }
            }
        }
        .padding(.bottom, 24)
        .animation(.easeOut(duration: 0.2), value: model.banner)
    }
}

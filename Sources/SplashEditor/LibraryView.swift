import SplashCore
import SwiftUI

/// The home of the app: your scenes, and presets to start from. Cards show the real scene, drawn by the same code as the wallpaper.
struct LibraryView: View {
    @Environment(AppModel.self) private var model
    private let columns = [GridItem(.adaptive(minimum: 250, maximum: 340), spacing: 20, alignment: .top)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 44) {
                if model.scenes.isEmpty {
                    header(title: "Make your desktop move.",
                           detail: "Start from a preset, change it with a few controls, or describe what you want to an AI agent you already use. Your wallpaper runs in a tiny background process, so the cost is almost nothing.")
                } else {
                    VStack(alignment: .leading, spacing: 20) {
                        header(title: "Your scenes", detail: nil)
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                            ForEach(model.scenes, id: \.manifest.id) { scene in
                                SceneCard(scene: scene)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 20) {
                    SectionLabel(text: model.scenes.isEmpty ? "Presets" : "Start from a preset")
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                        ForEach(Presets.all, id: \.id) { preset in
                            PresetCard(preset: preset)
                        }
                    }
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 36)
            .frame(maxWidth: 1180, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.never)
    }

    private func header(title: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 34, weight: .regular))
                .tracking(-1)
                .foregroundStyle(Theme.strong)
            if let detail {
                Text(detail)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.muted)
                    .lineSpacing(3)
                    .frame(maxWidth: 560, alignment: .leading)
            }
        }
    }
}

/// A picture with a caption. Shared by scene and preset cards.
struct CardFrame<Footer: View>: View {
    let image: NSImage?
    @ViewBuilder var footer: Footer
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Theme.surfaceRaised
                if let image {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill).transition(.opacity)
                }
            }
            .aspectRatio(16.0 / 10.0, contentMode: .fit)
            .clipped()
            Hairline()
            footer.padding(12)
        }
        .panel(radius: Theme.Radius.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).stroke(hovering ? Theme.borderStrong : .clear))
        .animation(.easeOut(duration: 0.18), value: image != nil)
        .onHover { hovering = $0 }
        .contentShape(Rectangle())
    }
}

struct SceneCard: View {
    @Environment(AppModel.self) private var model
    let scene: WallpaperScene

    var body: some View {
        Button { model.select(scene.manifest.id) } label: {
            CardFrame(image: model.thumbnails.image(forScene: scene.manifest.id)) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(scene.manifest.name).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.strong)
                        Text(scene.manifest.tiers.map(TopBar.tierName).joined(separator: " · "))
                            .font(.system(size: 12)).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    if model.applied?.sceneDirectory == scene.directory.path {
                        Badge(text: "On desktop", tint: Theme.green)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Open") { model.select(scene.manifest.id) }
            Button("Duplicate") { model.select(scene.manifest.id); model.duplicateSelected(); model.select(nil) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([scene.directory]) }
            Divider()
            Button("Delete", role: .destructive) { model.delete(scene) }
        }
    }
}

struct PresetCard: View {
    @Environment(AppModel.self) private var model
    let preset: Preset

    var body: some View {
        Button { model.create(from: preset) } label: {
            CardFrame(image: model.thumbnails.image(forPreset: preset.id)) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(preset.name).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.strong)
                        Spacer()
                        Text(preset.manifest.tiers.map(TopBar.tierName).joined(separator: " · "))
                            .font(.system(size: 12)).foregroundStyle(Theme.muted)
                    }
                    Text(preset.summary)
                        .font(.system(size: 12)).foregroundStyle(Theme.muted)
                        .lineLimit(2).multilineTextAlignment(.leading)
                }
            }
        }
        .buttonStyle(.plain)
        .help("Make a copy of this preset to edit")
    }
}

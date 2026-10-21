import AppKit
import SplashCore
import SplashPlatform
import SwiftUI
import UniformTypeIdentifiers

/// One scene: a large preview with an AI prompt under it, and an inspector on the right.
struct EditorView: View {
    @Environment(AppModel.self) private var model
    let scene: WallpaperScene

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    PreviewPane(scene: scene)
                    Conversation(chat: model.chat(for: scene))
                    Composer(chat: model.chat(for: scene))
                }
                .padding(24)
                .frame(maxWidth: 980)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.never)
            .modifier(FileDropModifier(chat: model.chat(for: scene)))
            Hairline(vertical: true)
            Inspector(scene: scene)
                .frame(width: 320)
                .background(Theme.surface)
        }
    }
}

// MARK: - Preview

struct PreviewPane: View {
    @Environment(AppModel.self) private var model
    let scene: WallpaperScene

    private var ratio: CGFloat {
        let size = NSScreen.main?.frame.size ?? CGSize(width: 16, height: 10)
        return size.width / size.height
    }

    var body: some View {
        @Bindable var annotations = model.annotations
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                Color.black
                ScenePreview(scene: scene, token: model.previewToken, paramsJSON: ParamStore.json(model.values), handle: model.preview)
                if annotations.isActive { AnnotationOverlay(model: annotations) }
            }
            .aspectRatio(ratio, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.panel).stroke(Theme.border))
            .overlay(alignment: .topTrailing) { floatingControls(annotations: annotations).padding(10) }
            .overlay(alignment: .topLeading) {
                if annotations.isActive { tools(annotations: annotations).padding(10) }
            }

            if !annotations.pins.isEmpty { PinList(model: annotations) }
        }
    }

    private func floatingControls(annotations: AnnotationModel) -> some View {
        HStack(spacing: 2) {
            Button { annotations.isActive.toggle() } label: { Image(systemName: "scribble") }
                .buttonStyle(IconButtonStyle(selected: annotations.isActive))
                .help("Draw and pin comments on the preview, then send them with your request")
            Button { model.reloadPreview() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(IconButtonStyle())
                .help("Load the scene again")
        }
        .padding(2)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).stroke(Theme.border))
    }

    private func tools(annotations: AnnotationModel) -> some View {
        @Bindable var annotations = annotations
        return HStack(spacing: 2) {
            ForEach(AnnotationModel.Tool.allCases) { tool in
                Button { annotations.tool = tool } label: { Label(tool.rawValue, systemImage: tool.symbol).labelStyle(.titleAndIcon) }
                    .buttonStyle(SplashButtonStyle(kind: annotations.tool == tool ? .primary : .ghost))
            }
            Button("Clear") { annotations.clear() }
                .buttonStyle(.splashGhost)
                .disabled(annotations.isEmpty)
        }
        .padding(2)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).stroke(Theme.border))
    }
}

struct PinList: View {
    @Bindable var model: AnnotationModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array($model.pins.enumerated()), id: \.element.id) { index, $pin in
                HStack(spacing: 8) {
                    Text("\(index + 1)")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 20, height: 20).background(Theme.red, in: Circle())
                    TextField("What should change here?", text: $pin.text)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                    Button { model.removePin(pin) } label: { Image(systemName: "xmark") }
                        .buttonStyle(IconButtonStyle())
                }
                .padding(.horizontal, 10).padding(.vertical, 4)
                .panel(radius: Theme.Radius.control)
            }
        }
    }
}

/// Shows the scene in a web view. The view is rebuilt when `token` changes; new parameter values reach it through the model.
struct ScenePreview: NSViewRepresentable {
    let scene: WallpaperScene
    let token: Int
    let paramsJSON: String
    let handle: PreviewHandle

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var key = ""
    }

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        install(in: container, context: context)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        let key = "\(scene.directory.path)#\(token)"
        if key != context.coordinator.key { install(in: container, context: context) }
    }

    private func install(in container: NSView, context: Context) {
        context.coordinator.key = "\(scene.directory.path)#\(token)"
        for view in container.subviews {
            (view as? SceneWebView)?.stopLoading()
            view.removeFromSuperview()
        }
        let view = SceneWebView(scene: scene, fps: min(scene.manifest.fps, 30), paramsJSON: paramsJSON, detail: 1.25, frame: container.bounds)
        view.autoresizingMask = [.width, .height]
        container.addSubview(view)
        handle.webView = view
    }

    static func dismantleNSView(_ container: NSView, coordinator: Coordinator) {
        for view in container.subviews { (view as? SceneWebView)?.stopLoading() }
    }
}

/// Drawing and pins over the preview. Positions are kept as fractions of the preview, so they do not depend on its size.
struct AnnotationOverlay: View {
    @Bindable var model: AnnotationModel

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                Canvas { context, canvasSize in
                    let all = model.strokes + (model.current.map { [$0] } ?? [])
                    for stroke in all where stroke.points.count > 1 {
                        var path = Path()
                        path.move(to: CGPoint(x: stroke.points[0].x * canvasSize.width, y: stroke.points[0].y * canvasSize.height))
                        for point in stroke.points.dropFirst() {
                            path.addLine(to: CGPoint(x: point.x * canvasSize.width, y: point.y * canvasSize.height))
                        }
                        context.stroke(path, with: .color(.red), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    }
                }
                ForEach(Array(model.pins.enumerated()), id: \.element.id) { index, pin in
                    Text("\(index + 1)").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 22, height: 22).background(Theme.red, in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 1.5))
                        .position(x: pin.x * size.width, y: pin.y * size.height)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard model.tool == .pen else { return }
                        let point = CGPoint(x: min(max(value.location.x / size.width, 0), 1), y: min(max(value.location.y / size.height, 0), 1))
                        if model.current == nil { model.current = Stroke(points: [point]) } else { model.current?.points.append(point) }
                    }
                    .onEnded { value in
                        if model.tool == .pen {
                            if let stroke = model.current { model.strokes.append(stroke) }
                            model.current = nil
                        } else {
                            model.pins.append(Pin(x: min(max(value.location.x / size.width, 0), 1), y: min(max(value.location.y / size.height, 0), 1)))
                        }
                    }
            )
        }
    }
}

// MARK: - Conversation with the agent

struct Conversation: View {
    @Environment(AppModel.self) private var model
    @Bindable var chat: ChatModel
    @State private var collapsed = false

    var body: some View {
        if !chat.messages.isEmpty {
            VStack(spacing: 0) {
                HStack {
                    SectionLabel(text: "Conversation")
                    Spacer()
                    Button { collapsed.toggle() } label: { Image(systemName: collapsed ? "chevron.down" : "chevron.up") }
                        .buttonStyle(IconButtonStyle())
                }
                .padding(.horizontal, 12).padding(.vertical, 4)
                if !collapsed {
                    Hairline()
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 10) {
                                ForEach(chat.messages) { MessageRow(message: $0).id($0.id) }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 230)
                        .onChange(of: chat.messages.count) { _, _ in
                            if let last = chat.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }
            }
            .panel(radius: Theme.Radius.panel)
        }
    }
}

struct MessageRow: View {
    let message: ChatMessage

    var body: some View {
        switch message.kind {
        case .user:
            VStack(alignment: .trailing, spacing: 6) {
                if let path = message.imagePath, let image = NSImage(contentsOfFile: path) {
                    Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: 220)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control))
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control).stroke(Theme.border))
                }
                Text(message.text)
                    .font(.system(size: 13))
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
                ForEach(message.attachments, id: \.self) { name in
                    Label(name, systemImage: "paperclip").font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        case .agent:
            Text(message.text).font(.system(size: 13)).lineSpacing(2).textSelection(.enabled)
        case .activity:
            Label(message.text, systemImage: "chevron.right")
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.muted)
        case .error:
            Label(message.text, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12)).foregroundStyle(Theme.red).textSelection(.enabled)
        case .note:
            Text(message.text).font(.system(size: 12)).foregroundStyle(Theme.muted)
        }
    }
}

/// The prompt: describe a change in words, with files and an optional drawing. It always says which agent, and which model,
/// is going to read it.
struct Composer: View {
    @Environment(AppModel.self) private var model
    @Bindable var chat: ChatModel
    @State private var draft = ""
    @State private var includeDrawing = true
    @State private var askingForModel = false
    @State private var customModel = ""
    @FocusState private var focused: Bool

    var body: some View {
        let agents = chat.installedAgents
        VStack(alignment: .leading, spacing: 10) {
            if !chat.attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(chat.attachments) { AttachmentChip(chat: chat, item: $0) }
                    }
                }
            }
            if !model.annotations.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "scribble").foregroundStyle(Theme.muted)
                    Text("\(model.annotations.strokes.count) strokes, \(model.annotations.pins.count) pins")
                        .font(.system(size: 12)).foregroundStyle(Theme.muted)
                    Spacer()
                    Toggle("Send with request", isOn: $includeDrawing).toggleStyle(.switch).controlSize(.mini)
                        .font(.system(size: 12))
                }
            }
            TextField(agents.isEmpty ? "Install Claude Code or Codex to describe changes in words" : "Describe a change, or draw on the preview…",
                      text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .lineLimit(1...6)
                .focused($focused)
                .disabled(chat.isRunning || agents.isEmpty)
                .onSubmit(send)

            HStack(spacing: 8) {
                Button(action: chooseFiles) { Image(systemName: "paperclip") }
                    .buttonStyle(IconButtonStyle())
                    .help("Attach images, SVGs, videos or other files: to use in the scene, or as a reference. You can also drop them here.")
                    .disabled(chat.isRunning || agents.isEmpty)

                if agents.isEmpty {
                    Badge(text: "No agent found", tint: Theme.red)
                } else {
                    agentMenu(agents)
                    modelMenu
                }
                Spacer()
                if chat.isRunning {
                    ProgressView().controlSize(.small)
                    Button { chat.cancel() } label: { Image(systemName: "stop.fill") }
                        .buttonStyle(SplashButtonStyle(kind: .secondary)).help("Stop the agent")
                } else {
                    Button(action: send) { Image(systemName: "arrow.up").font(.system(size: 12, weight: .bold)) }
                        .buttonStyle(.splashPrimary)
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || agents.isEmpty)
                        .help("Send")
                }
            }
            if !agents.isEmpty {
                Text("Runs \(chat.agent.displayName) with your own login: \(chat.agent.provider == "chosen in OpenCode" ? "the provider is the one you set in OpenCode" : "your prompt, attached files and drawing go to \(chat.agent.provider)"). No API key in Splash.")
                    .font(.system(size: 11)).foregroundStyle(Theme.muted.opacity(0.8))
            }
        }
        .padding(14)
        .panel(radius: Theme.Radius.panel)
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.panel).stroke(focused ? Theme.borderStrong : .clear))
        .alert("Model name", isPresented: $askingForModel) {
            TextField(chat.agent.modelHint, text: $customModel)
            Button("Use it") { chat.setModel(customModel.trimmingCharacters(in: .whitespaces)) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The name is passed to \(chat.agent.displayName) as it is. Leave it empty for the agent's own default.")
        }
    }

    /// Which agent, and whose models it uses.
    private func agentMenu(_ agents: [AgentKind]) -> some View {
        Menu {
            ForEach(agents) { agent in
                Button { chat.agent = agent } label: {
                    Label("\(agent.displayName) · \(agent.provider)", systemImage: agent == chat.agent ? "checkmark" : "")
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(chat.agent.displayName).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text)
                Text(chat.agent.provider).font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
        }
        .menuStyle(.borderlessButton).menuIndicator(.visible).fixedSize()
        .help("The agent that makes the changes")
    }

    private var modelMenu: some View {
        Menu {
            ForEach(chat.agent.modelOptions, id: \.self) { option in
                Button { chat.setModel(option.value ?? "") } label: {
                    Label(option.value == nil ? "Default (the agent's own choice)" : option.label,
                          systemImage: (option.value ?? "") == chat.model ? "checkmark" : "")
                }
            }
            Divider()
            Button("Other model…") { customModel = chat.model; askingForModel = true }
        } label: {
            HStack(spacing: 5) {
                Text("Model").font(.system(size: 12)).foregroundStyle(Theme.muted)
                Text(chat.modelLabel).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text)
            }
        }
        .menuStyle(.borderlessButton).menuIndicator(.visible).fixedSize()
        .help("The model the agent uses for this request")
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Choose images, SVGs, videos or other files to give to the AI."
        if panel.runModal() == .OK { chat.attach(panel.urls) }
    }

    private func send() {
        chat.send(draft, includeAnnotations: includeDrawing)
        draft = ""
    }
}

/// A file waiting to be sent, with the choice of what it is for.
struct AttachmentChip: View {
    @Bindable var chat: ChatModel
    let item: PendingAttachment

    var body: some View {
        HStack(spacing: 8) {
            thumbnail
            Text(item.url.lastPathComponent).font(.system(size: 12)).lineLimit(1).frame(maxWidth: 150, alignment: .leading)
            Menu {
                Button { chat.setRole(.use, for: item.id) } label: {
                    Label("Use in the scene", systemImage: item.role == .use ? "checkmark" : "")
                }
                Button { chat.setRole(.reference, for: item.id) } label: {
                    Label("Only as a reference", systemImage: item.role == .reference ? "checkmark" : "")
                }
            } label: {
                Text(item.role == .use ? "In the scene" : "Reference")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(item.role == .use ? Theme.green : Theme.blue)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help(item.kind == .video ? "A video in the scene can only be live. As a reference, the agent looks at pictures taken from it."
                                      : "In the scene: the agent can use the file. Reference: the agent only looks at it.")
            Button { chat.removeAttachment(item.id) } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                .buttonStyle(.plain).foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .panel(radius: Theme.Radius.control, fill: Theme.surfaceRaised)
    }

    @ViewBuilder private var thumbnail: some View {
        if item.kind == .image || item.kind == .svg, let image = NSImage(contentsOf: item.url) {
            Image(nsImage: image).resizable().scaledToFill().frame(width: 22, height: 22).clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            Image(systemName: item.kind == .video ? "film" : item.kind == .model ? "cube" : "doc")
                .frame(width: 22, height: 22).foregroundStyle(Theme.muted)
        }
    }
}

/// Lets files be dropped on a view and handed to the chat.
struct FileDropModifier: ViewModifier {
    let chat: ChatModel
    @State private var targeted = false

    func body(content: Content) -> some View {
        content
            .onDrop(of: [UTType.fileURL], isTargeted: $targeted) { providers in
                var accepted = false
                for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    accepted = true
                    provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                        guard let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                        Task { @MainActor in chat.attach([url]) }
                    }
                }
                return accepted
            }
            .overlay {
                if targeted {
                    RoundedRectangle(cornerRadius: Theme.Radius.panel).stroke(Theme.blue, style: StrokeStyle(lineWidth: 2, dash: [6]))
                        .background(Theme.blue.opacity(0.06))
                        .overlay(Label("Drop to give it to the AI", systemImage: "paperclip").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.blue))
                        .allowsHitTesting(false)
                }
            }
    }
}

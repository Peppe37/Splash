import AppKit
import SwiftUI

/// The visual system. Flat surfaces separated by 1 px borders instead of shadows, warm neutrals, near-black for the strongest contrast,
/// small corner radii, and colour reserved for status. Light is cream and white; dark is near-black.
enum Theme {
    static let bg = Color.adaptive(light: 0xF6F5F1, dark: 0x0A0A0A)
    static let surface = Color.adaptive(light: 0xFFFFFF, dark: 0x141414)
    static let surfaceRaised = Color.adaptive(light: 0xF0EFEA, dark: 0x1B1B1B)
    static let border = Color.adaptive(light: 0xE0DFDB, dark: 0x2A2A2A)
    static let borderStrong = Color.adaptive(light: 0xBDBCB6, dark: 0x4A4A4A)
    static let text = Color.adaptive(light: 0x1A1A1A, dark: 0xE5E5E5)
    /// Headings and filled buttons.
    static let strong = Color.adaptive(light: 0x0A0A0A, dark: 0xFFFFFF)
    static let muted = Color.adaptive(light: 0x6B6A66, dark: 0x8C8C86)
    static let green = Color.adaptive(light: 0x1A7A0A, dark: 0x22C55E)
    static let blue = Color.adaptive(light: 0x2563EB, dark: 0x3B82F6)
    static let purple = Color.adaptive(light: 0x7C3AED, dark: 0xA78BFA)
    static let red = Color.adaptive(light: 0xC2410C, dark: 0xF97316)

    enum Radius {
        static let badge: CGFloat = 4
        static let control: CGFloat = 6
        static let card: CGFloat = 8
        static let panel: CGFloat = 12
    }

    static let nsBackground = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(srgbHex: 0x0A0A0A) : NSColor(srgbHex: 0xF6F5F1)
    }
}

extension NSColor {
    convenience init(srgbHex hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension Color {
    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(srgbHex: dark) : NSColor(srgbHex: light)
        })
    }
}

// MARK: - Buttons

struct SplashButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, ghost }
    var kind: Kind = .secondary
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 12)
            .frame(height: 28)
            .foregroundStyle(foreground)
            .background(background(pressed: configuration.isPressed), in: RoundedRectangle(cornerRadius: Theme.Radius.control))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control).stroke(kind == .primary ? .clear : Theme.border))
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control))
    }

    private var foreground: Color { kind == .primary ? Theme.bg : Theme.text }

    private func background(pressed: Bool) -> Color {
        switch kind {
        case .primary: return Theme.strong.opacity(pressed ? 0.8 : 1)
        case .secondary: return pressed ? Theme.surfaceRaised : Theme.surface
        case .ghost: return pressed ? Theme.surfaceRaised : .clear
        }
    }
}

struct IconButtonStyle: ButtonStyle {
    var selected = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .frame(width: 28, height: 28)
            .foregroundStyle(selected ? Theme.bg : Theme.text)
            .background(selected ? Theme.strong : (configuration.isPressed ? Theme.surfaceRaised : .clear), in: RoundedRectangle(cornerRadius: Theme.Radius.control))
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Rectangle())
    }
}

extension ButtonStyle where Self == SplashButtonStyle {
    static var splashPrimary: SplashButtonStyle { SplashButtonStyle(kind: .primary) }
    static var splash: SplashButtonStyle { SplashButtonStyle(kind: .secondary) }
    static var splashGhost: SplashButtonStyle { SplashButtonStyle(kind: .ghost) }
}

// MARK: - Pieces

/// A small tinted label, like a status tag.
struct Badge: View {
    let text: String
    var tint: Color = Theme.muted

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .frame(height: 18)
            .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.Radius.badge))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.badge).stroke(tint.opacity(0.25)))
    }
}

struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .medium))
            .tracking(0.6)
            .foregroundStyle(Theme.muted)
    }
}

struct Hairline: View {
    var vertical = false

    var body: some View {
        Theme.border.frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
    }
}

/// A flat bordered surface.
struct Panel: ViewModifier {
    var radius: CGFloat = Theme.Radius.card
    var fill: Color = Theme.surface

    func body(content: Content) -> some View {
        content
            .background(fill, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(Theme.border))
    }
}

extension View {
    func panel(radius: CGFloat = Theme.Radius.card, fill: Color = Theme.surface) -> some View {
        modifier(Panel(radius: radius, fill: fill))
    }
}

/// Tabs as a row of text with a thin underline, like the navigation of a documentation site.
struct TabRow<Value: Hashable & Identifiable>: View {
    let values: [Value]
    @Binding var selection: Value
    let title: (Value) -> String
    @Namespace private var underline

    var body: some View {
        HStack(spacing: 16) {
            ForEach(values) { value in
                Button { withAnimation(.easeOut(duration: 0.15)) { selection = value } } label: {
                    Text(title(value))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(selection == value ? Theme.strong : Theme.muted)
                        .padding(.vertical, 10)
                        .overlay(alignment: .bottom) {
                            if selection == value { Theme.strong.frame(height: 1).matchedGeometryEffect(id: "underline", in: underline) }
                        }
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
    }
}

/// Makes the window's title bar part of the content: traffic lights stay, the bar's background and title go.
struct WindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = true
            window.backgroundColor = Theme.nsBackground
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

import AppKit

// Draws the Splash app icon: a dark squircle with a gradient drop and two small droplets.
// Usage: swift scripts/make_icon.swift <output.png> [size]
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let size = CommandLine.arguments.count > 2 ? Double(CommandLine.arguments[2]) ?? 1024 : 1024

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let s = CGFloat(size)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

// Squircle, with the margin macOS icons have.
let inset = s * 0.098
let body = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
let squircle = CGPath(roundedRect: body, cornerWidth: body.width * 0.2237, cornerHeight: body.width * 0.2237, transform: nil)
context.saveGState()
context.addPath(squircle)
context.clip()
let background = CGGradient(colorsSpace: space, colors: [color(0x1B1B1B), color(0x070707)] as CFArray, locations: [0, 1])!
context.drawLinearGradient(background, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])

// A soft glow behind the drop.
let glow = CGGradient(colorsSpace: space, colors: [color(0x3B82F6, 0.35), color(0x3B82F6, 0)] as CFArray, locations: [0, 1])!
context.drawRadialGradient(glow, startCenter: CGPoint(x: s * 0.5, y: s * 0.46), startRadius: 0,
                           endCenter: CGPoint(x: s * 0.5, y: s * 0.46), endRadius: s * 0.42, options: [])

// The drop: a circle with a point on top. The sides are tangent to the circle, with a slight curve in.
func drop(center: CGPoint, radius r: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let reach = r * 2.25
    let tip = CGPoint(x: center.x, y: center.y + reach)
    let theta = acos(r / reach)
    let left = CGPoint(x: center.x - r * sin(theta), y: center.y + r * cos(theta))
    let right = CGPoint(x: center.x + r * sin(theta), y: center.y + r * cos(theta))
    let inward = r * 0.10
    path.move(to: tip)
    path.addQuadCurve(to: left, control: CGPoint(x: (tip.x + left.x) / 2 + inward, y: (tip.y + left.y) / 2 + inward * 0.4))
    path.addArc(center: center, radius: r, startAngle: .pi / 2 + theta, endAngle: .pi / 2 - theta, clockwise: false)
    path.addQuadCurve(to: tip, control: CGPoint(x: (tip.x + right.x) / 2 - inward, y: (tip.y + right.y) / 2 + inward * 0.4))
    path.closeSubpath()
    return path
}

let main = drop(center: CGPoint(x: s * 0.5, y: s * 0.36), radius: s * 0.17)
context.saveGState()
context.addPath(main)
context.clip()
let fill = CGGradient(colorsSpace: space, colors: [color(0x22C55E), color(0x3B82F6), color(0xA78BFA)] as CFArray, locations: [0, 0.5, 1])!
context.drawLinearGradient(fill, start: CGPoint(x: s * 0.40, y: s * 0.78), end: CGPoint(x: s * 0.62, y: s * 0.19), options: [])
// A highlight.
let highlight = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF, 0.5), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
context.drawRadialGradient(highlight, startCenter: CGPoint(x: s * 0.45, y: s * 0.41), startRadius: 0,
                           endCenter: CGPoint(x: s * 0.45, y: s * 0.41), endRadius: s * 0.11, options: [])
context.restoreGState()

// Two small droplets, as if the drop had just landed.
for (x, y, r, c) in [(0.25, 0.30, 0.035, 0x22C55E), (0.77, 0.27, 0.028, 0xA78BFA), (0.70, 0.61, 0.02, 0x3B82F6)] as [(CGFloat, CGFloat, CGFloat, UInt32)] {
    context.setFillColor(color(UInt32(c)))
    context.fillEllipse(in: CGRect(x: s * x - s * r, y: s * y - s * r, width: s * r * 2, height: s * r * 2))
}
context.restoreGState()

// A 1 px edge so the icon holds its shape on dark backgrounds.
context.addPath(squircle)
context.setStrokeColor(color(0xFFFFFF, 0.08))
context.setLineWidth(max(1, s / 512))
context.strokePath()

let image = context.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))

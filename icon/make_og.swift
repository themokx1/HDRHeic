// Renders the 1200×630 social preview card (Open Graph / Twitter) for the
// downloads page: the app icon on the brand gradient with the name + tagline.
// Usage: swift make_og.swift <icon.png> <out.png>

import AppKit

let iconPath = CommandLine.arguments[1]
let outPath = CommandLine.arguments[2]
let width: CGFloat = 1200, height: CGFloat = 630

func color(_ r: Int, _ g: Int, _ b: Int) -> NSColor {
    NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
}

let image = NSImage(size: NSSize(width: width, height: height))
image.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else { exit(1) }

// Same sunset gradient as the app icon.
let gradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [color(58, 28, 113).cgColor, color(215, 109, 119).cgColor, color(255, 175, 123).cgColor] as CFArray,
    locations: [0.0, 0.55, 1.0]
)!
ctx.drawLinearGradient(gradient,
                       start: CGPoint(x: 0, y: height),
                       end: CGPoint(x: width, y: 0),
                       options: [])

// App icon, left of the text.
let iconSize: CGFloat = 260
let iconRect = NSRect(x: 110, y: (height - iconSize) / 2, width: iconSize, height: iconSize)
if let icon = NSImage(contentsOfFile: iconPath) {
    let radius = iconSize * 0.2237
    let path = NSBezierPath(roundedRect: iconRect, xRadius: radius, yRadius: radius)
    // Drop shadow so the icon separates from the same-gradient background.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 34,
                  color: NSColor.black.withAlphaComponent(0.45).cgColor)
    NSColor.black.setFill()
    path.fill()
    ctx.restoreGState()
    // Rounded corners to match how macOS presents the icon.
    ctx.saveGState()
    path.addClip()
    icon.draw(in: iconRect)
    ctx.restoreGState()
}

func draw(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: NSColor.white.withAlphaComponent(alpha),
    ]
    NSAttributedString(string: text, attributes: attributes)
        .draw(at: NSPoint(x: x, y: y))
}

let textX: CGFloat = 430
draw("HDRHeic", x: textX, y: 355, size: 92, weight: .bold, alpha: 1.0)
draw("HDR JPEG → 10-bit HDR HEIC", x: textX, y: 292, size: 38, weight: .medium, alpha: 0.95)
draw("Automatic, native, gain-map preserving.", x: textX, y: 232, size: 28, weight: .regular, alpha: 0.8)
draw("macOS", x: textX, y: 160, size: 24, weight: .semibold, alpha: 0.7)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { exit(2) }
try? png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")

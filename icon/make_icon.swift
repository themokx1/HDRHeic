// Renders a 1024×1024 app icon PNG: a rounded-rect "sunset" gradient (evoking
// photographic dynamic range) with a white sun. Output path is argv[1].
// Usage: swift make_icon.swift out.png

import AppKit

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
let size: CGFloat = 1024

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else { exit(1) }

// Rounded-rect clip (macOS icon corner ≈ 22.37% of the side).
let rect = CGRect(x: 0, y: 0, width: size, height: size)
let radius = size * 0.2237
ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
ctx.clip()

// Diagonal "sunset" gradient: deep indigo → warm rose → soft amber.
func color(_ r: Int, _ g: Int, _ b: Int) -> CGColor {
    NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1).cgColor
}
let gradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [color(58, 28, 113), color(215, 109, 119), color(255, 175, 123)] as CFArray,
    locations: [0.0, 0.55, 1.0]
)!
ctx.drawLinearGradient(gradient,
                       start: CGPoint(x: 0, y: size),
                       end: CGPoint(x: size, y: 0),
                       options: [])

// White sun, centered.
let sunCenter = CGPoint(x: size / 2, y: size * 0.5)
let sunRadius = size * 0.185
ctx.setFillColor(NSColor.white.cgColor)
ctx.addArc(center: sunCenter, radius: sunRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
ctx.fillPath()

// Sun rays.
let rayCount = 12
let rayInner = sunRadius * 1.35
let rayOuter = sunRadius * 1.95
let rayWidth = size * 0.022
ctx.setStrokeColor(NSColor.white.cgColor)
ctx.setLineWidth(rayWidth)
ctx.setLineCap(.round)
for i in 0..<rayCount {
    let angle = CGFloat(i) / CGFloat(rayCount) * .pi * 2
    let start = CGPoint(x: sunCenter.x + cos(angle) * rayInner, y: sunCenter.y + sin(angle) * rayInner)
    let end = CGPoint(x: sunCenter.x + cos(angle) * rayOuter, y: sunCenter.y + sin(angle) * rayOuter)
    ctx.move(to: start)
    ctx.addLine(to: end)
    ctx.strokePath()
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { exit(2) }
try? png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")

// Generates Resources/AppIcon.icns by rendering a sakura-petal mark with
// CoreGraphics. Run: swift scripts/make_icon.swift
import AppKit
import CoreGraphics

let size = 1024
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size,
    pixelsHigh: size,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .calibratedRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else { fatalError("bitmap") }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
guard let ctx = NSGraphicsContext.current?.cgContext else { fatalError("context") }

let s = CGFloat(size)

// Rounded-square background with a soft vertical gradient (light → dark).
let bgRect = CGRect(x: s * 0.04, y: s * 0.04, width: s * 0.92, height: s * 0.92)
let bgPath = CGPath(roundedRect: bgRect, cornerWidth: s * 0.20, cornerHeight: s * 0.20, transform: nil)
ctx.addPath(bgPath)
ctx.clip()
let colors = [
    CGColor(red: 0.98, green: 0.86, blue: 0.90, alpha: 1),
    CGColor(red: 0.91, green: 0.55, blue: 0.66, alpha: 1),
] as CFArray
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: s / 2, y: s), end: CGPoint(x: s / 2, y: 0), options: [])

// Five-petal sakura blossom.
func petal(center: CGPoint, angle: CGFloat, length: CGFloat, width: CGFloat, color: CGColor) {
    let path = CGMutablePath()
    let tip = CGPoint(x: center.x + cos(angle) * length, y: center.y + sin(angle) * length)
    let side1 = CGPoint(x: center.x + cos(angle + .pi / 2) * width, y: center.y + sin(angle + .pi / 2) * width)
    let side2 = CGPoint(x: center.x + cos(angle - .pi / 2) * width, y: center.y + sin(angle - .pi / 2) * width)
    path.move(to: center)
    path.addQuadCurve(to: tip, control: CGPoint(x: side1.x + cos(angle) * length * 0.35, y: side1.y + sin(angle) * length * 0.35))
    path.addQuadCurve(to: center, control: CGPoint(x: side2.x + cos(angle) * length * 0.35, y: side2.y + sin(angle) * length * 0.35))
    path.closeSubpath()
    ctx.addPath(path)
    ctx.setFillColor(color)
    ctx.fillPath()
}

let center = CGPoint(x: s * 0.5, y: s * 0.52)
let petalColor = CGColor(red: 1.0, green: 0.94, blue: 0.96, alpha: 0.98)
let petalShadow = CGColor(red: 0.86, green: 0.45, blue: 0.57, alpha: 0.55)
for i in 0..<5 {
    let angle = CGFloat(i) / 5 * 2 * .pi - .pi / 2
    // Petals are notched at the tip (classic sakura shape) — approximate with
    // two overlapping lobes.
    petal(center: center, angle: angle, length: s * 0.30, width: s * 0.165, color: petalColor)
    petal(center: CGPoint(x: center.x + cos(angle) * s * 0.08, y: center.y + sin(angle) * s * 0.08),
          angle: angle + 0.26, length: s * 0.19, width: s * 0.10, color: petalShadow)
    petal(center: CGPoint(x: center.x + cos(angle) * s * 0.08, y: center.y + sin(angle) * s * 0.08),
          angle: angle - 0.26, length: s * 0.19, width: s * 0.10, color: petalShadow)
}

// Stamen center.
ctx.setFillColor(CGColor(red: 0.98, green: 0.80, blue: 0.42, alpha: 1))
ctx.fillEllipse(in: CGRect(x: center.x - s * 0.075, y: center.y - s * 0.075, width: s * 0.15, height: s * 0.15))
ctx.setFillColor(CGColor(red: 0.86, green: 0.60, blue: 0.20, alpha: 1))
for i in 0..<8 {
    let angle = CGFloat(i) / 8 * 2 * .pi
    let x = center.x + cos(angle) * s * 0.045
    let y = center.y + sin(angle) * s * 0.045
    ctx.fillEllipse(in: CGRect(x: x - s * 0.011, y: y - s * 0.011, width: s * 0.022, height: s * 0.022))
}

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png") }

// Write PNG set for iconutil.
let fileManager = FileManager.default
let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let iconset = scriptDir.appendingPathComponent("AppIcon.iconset")
try? fileManager.removeItem(at: iconset)
try fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)

let sizes: [(Int, String)] = [
    (16, "icon_16x16"), (32, "icon_16x16@2x"),
    (32, "icon_32x32"), (64, "icon_32x32@2x"),
    (128, "icon_128x128"), (256, "icon_128x128@2x"),
    (256, "icon_256x256"), (512, "icon_256x256@2x"),
    (512, "icon_512x512"), (1024, "icon_512x512@2x"),
]

let image = NSImage(cgImage: rep.cgImage!, size: NSSize(width: size, height: size))
for (px, name) in sizes {
    let scaled = NSImage(size: NSSize(width: px, height: px))
    scaled.lockFocus()
    image.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    scaled.unlockFocus()
    guard let tiff = scaled.tiffRepresentation,
          let scaledRep = NSBitmapImageRep(data: tiff),
          let data = scaledRep.representation(using: .png, properties: [:]) else { continue }
    try data.write(to: iconset.appendingPathComponent("\(name).png"))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", scriptDir.deletingLastPathComponent().appendingPathComponent("Resources/AppIcon.icns").path]
try process.run()
process.waitUntilExit()
try? fileManager.removeItem(at: iconset)
print("AppIcon.icns written to Resources/")

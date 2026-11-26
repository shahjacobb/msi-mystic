// Renders Resources/AppIcon.icns from Resources/msi-logo.png.
// Usage: swift scripts/make-icon.swift

import AppKit
import CoreImage

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let resources = root.appendingPathComponent("Resources")
let side: CGFloat = 1024

func render() -> CGImage {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: Int(side), height: Int(side), bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

    // Tile: macOS icon grid, 824pt body with continuous corners.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tile = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)
    ctx.saveGState()
    ctx.addPath(tile)
    ctx.clip()
    let bg = CGGradient(colorsSpace: space, colors: [
        CGColor(red: 0.13, green: 0.13, blue: 0.15, alpha: 1),
        CGColor(red: 0.03, green: 0.03, blue: 0.04, alpha: 1),
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

    // Spectrum ring, drawn as short hue arcs, then blurred for glow.
    let center = CGPoint(x: 512, y: 512)
    let ring = CGContext(data: nil, width: Int(side), height: Int(side), bitsPerComponent: 8, bytesPerRow: 0,
                         space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let steps = 360
    for i in 0..<steps {
        let a0 = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let a1 = CGFloat(i + 1) / CGFloat(steps) * 2 * .pi + 0.01
        let c = NSColor(hue: CGFloat(i) / CGFloat(steps), saturation: 0.95, brightness: 1, alpha: 1)
        ring.setStrokeColor(c.cgColor)
        ring.setLineWidth(26)
        ring.addArc(center: center, radius: 300, startAngle: a0, endAngle: a1, clockwise: false)
        ring.strokePath()
    }
    let ringImage = ring.makeImage()!
    let ci = CIImage(cgImage: ringImage)
    let glow = ci.applyingGaussianBlur(sigma: 40).cropped(to: ci.extent)
    let ciContext = CIContext()
    let glowImage = ciContext.createCGImage(glow, from: ci.extent)!
    ctx.setAlpha(0.9)
    ctx.draw(glowImage, in: CGRect(x: 0, y: 0, width: side, height: side))
    ctx.setAlpha(1)
    ctx.draw(ringImage, in: CGRect(x: 0, y: 0, width: side, height: side))

    // Wordmark, tinted white.
    let logo = NSImage(contentsOf: resources.appendingPathComponent("msi-logo.png"))!
    var rect = CGRect(origin: .zero, size: logo.size)
    let logoCG = logo.cgImage(forProposedRect: &rect, context: nil, hints: nil)!
    let w: CGFloat = 340
    let h = w * CGFloat(logoCG.height) / CGFloat(logoCG.width)
    let logoRect = CGRect(x: center.x - w / 2, y: center.y - h / 2, width: w, height: h)
    ctx.saveGState()
    ctx.clip(to: logoRect, mask: logoCG)
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fill(logoRect)
    ctx.restoreGState()

    // Hairline edge.
    ctx.restoreGState()
    ctx.addPath(tile)
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.08))
    ctx.setLineWidth(2)
    ctx.strokePath()

    return ctx.makeImage()!
}

let master = render()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = base * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        NSGraphicsContext.current?.cgContext.draw(master, in: CGRect(x: 0, y: 0, width: px, height: px))
        NSGraphicsContext.restoreGraphicsState()
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try! rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}

let out = resources.appendingPathComponent("AppIcon.icns")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try! task.run()
task.waitUntilExit()

let preview = NSBitmapImageRep(cgImage: master).representation(using: .png, properties: [:])!
try! preview.write(to: resources.appendingPathComponent("icon-preview.png"))
print("Wrote \(out.path)")

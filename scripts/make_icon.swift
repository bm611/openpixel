import AppKit
import Foundation

let directory = URL(fileURLWithPath: ".build/OpenPixel.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let opacity: [CGFloat] = [0.25, 0.7, 0, 0.7, 1, 0.65, 0, 0.65, 0.25]
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let size = base * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size,
            pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let dimension = CGFloat(size)
        NSColor(calibratedRed: 0.14, green: 0.15, blue: 0.15, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: dimension * 0.05, y: dimension * 0.05,
            width: dimension * 0.9, height: dimension * 0.9),
            xRadius: dimension * 0.20, yRadius: dimension * 0.20).fill()
        let cell = dimension * 0.145
        let gap = dimension * 0.045
        let origin = (dimension - 3 * cell - 2 * gap) / 2
        for row in 0..<3 {
            for column in 0..<3 {
                let alpha = opacity[row * 3 + column]
                NSColor(calibratedRed: 0.98, green: 0.53, blue: 0.34, alpha: alpha).setFill()
                NSBezierPath(roundedRect: NSRect(
                    x: origin + CGFloat(column) * (cell + gap),
                    y: origin + CGFloat(2 - row) * (cell + gap), width: cell, height: cell),
                    xRadius: dimension * 0.025, yRadius: dimension * 0.025).fill()
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        let target = directory.appendingPathComponent("icon_\(base)x\(base)\(suffix).png")
        try bitmap.representation(using: .png, properties: [:])!.write(to: target)
    }
}


import AppKit
import Foundation

let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: CGFloat(pixels) / 512, y: CGFloat(pixels) / 512)
        NSColor(calibratedRed: 0.32, green: 0.27, blue: 0.75, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 22, y: 22, width: 468, height: 468), xRadius: 108, yRadius: 108).fill()
        NSColor.white.withAlphaComponent(0.20).setFill()
        NSBezierPath(roundedRect: NSRect(x: 115, y: 102, width: 282, height: 305), xRadius: 28, yRadius: 28).fill()
        NSColor.white.setFill()
        NSBezierPath(roundedRect: NSRect(x: 98, y: 123, width: 282, height: 305), xRadius: 28, yRadius: 28).fill()
        let text = "?" as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 195, weight: .semibold), .foregroundColor: NSColor(calibratedRed: 0.32, green: 0.27, blue: 0.75, alpha: 1)]
        let textSize = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: 239 - textSize.width / 2, y: 179), withAttributes: attributes)
        NSColor(calibratedRed: 0.84, green: 0.82, blue: 0.95, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 158, y: 159, width: 162, height: 12), xRadius: 6, yRadius: 6).fill()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        let file = destination.appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
        try bitmap.representation(using: .png, properties: [:])!.write(to: file)
    }
}

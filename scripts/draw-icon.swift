import AppKit

let output = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let scale = CGFloat(size) / 1024
    let bounds = NSRect(x: 88 * scale, y: 88 * scale, width: 848 * scale, height: 848 * scale)
    let shape = NSBezierPath(roundedRect: bounds, xRadius: 190 * scale, yRadius: 190 * scale)
    NSGradient(starting: NSColor(calibratedRed: 0.99, green: 0.91, blue: 0.73, alpha: 1),
               ending: NSColor(calibratedRed: 0.88, green: 0.64, blue: 0.29, alpha: 1))!.draw(in: shape, angle: -90)
    if let icon = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil) {
        let config = NSImage.SymbolConfiguration(pointSize: 450 * scale, weight: .medium)
            .applying(.init(paletteColors: [NSColor(calibratedRed: 0.38, green: 0.22, blue: 0.08, alpha: 1)]))
        icon.withSymbolConfiguration(config)?.draw(in: NSRect(x: 245 * scale, y: 270 * scale, width: 540 * scale, height: 480 * scale))
    }
    NSGraphicsContext.restoreGraphicsState()
    let png = bitmap.representation(using: .png, properties: [:])!
    try png.write(to: URL(fileURLWithPath: output).appendingPathComponent("icon_\(size)x\(size).png"))
}

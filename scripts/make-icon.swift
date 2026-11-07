import AppKit

let directory = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
var chunks = Data()
func bigEndian(_ value: Int) -> Data {
    var number = UInt32(value).bigEndian
    return withUnsafeBytes(of: &number) { Data($0) }
}
let types = [16: ["icp4", "ic11"], 32: ["icp5", "ic12"], 128: ["ic07", "ic13"],
             256: ["ic08", "ic14"], 512: ["ic09", "ic10"]]
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let background = NSBezierPath(roundedRect: NSRect(x: 60, y: 60, width: 904, height: 904), xRadius: 210, yRadius: 210)
        let gradient = NSGradient(starting: NSColor(srgbRed: 0.22, green: 0.62, blue: 0.98, alpha: 1),
                                  ending: NSColor(srgbRed: 0.32, green: 0.26, blue: 0.86, alpha: 1))!
        gradient.draw(in: background, angle: -60)
        // A mouse seen from above, with its two buttons and scroll wheel.
        let shadow = NSBezierPath(roundedRect: NSRect(x: 322, y: 160, width: 380, height: 640), xRadius: 190, yRadius: 190)
        NSColor(white: 0, alpha: 0.2).setFill()
        shadow.fill()
        let body = NSBezierPath(roundedRect: NSRect(x: 322, y: 190, width: 380, height: 640), xRadius: 190, yRadius: 190)
        NSColor(white: 0.98, alpha: 1).setFill()
        body.fill()
        let line = NSColor(srgbRed: 0.72, green: 0.74, blue: 0.82, alpha: 1)
        line.setStroke()
        let seam = NSBezierPath()
        seam.lineWidth = 14
        seam.lineCapStyle = .round
        seam.move(to: NSPoint(x: 340, y: 590))
        seam.line(to: NSPoint(x: 684, y: 590))
        seam.move(to: NSPoint(x: 512, y: 590))
        seam.line(to: NSPoint(x: 512, y: 812))
        seam.stroke()
        let wheel = NSBezierPath(roundedRect: NSRect(x: 484, y: 640, width: 56, height: 120), xRadius: 28, yRadius: 28)
        NSColor(srgbRed: 0.32, green: 0.36, blue: 0.86, alpha: 1).setFill()
        wheel.fill()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        let png = bitmap.representation(using: .png, properties: [:])!
        try png.write(to: directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
        // Modern ICNS entries contain PNG data. Write the container directly so the
        // build also works where iconutil's image conversion service is unavailable.
        chunks.append(Data(types[size]![scale - 1].utf8))
        chunks.append(bigEndian(png.count + 8))
        chunks.append(png)
    }
}
var icon = Data("icns".utf8)
icon.append(bigEndian(chunks.count + 8))
icon.append(chunks)
try icon.write(to: directory.deletingLastPathComponent().appendingPathComponent("AppIcon.icns"))

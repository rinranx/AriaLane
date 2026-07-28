import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("usage: swift generate_icon.swift <iconset-directory>\n", stderr)
    exit(2)
}

let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(
    at: destination,
    withIntermediateDirectories: true
)

let outputs: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1_024)
]

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
}

func renderIcon(pixelSize: Int) throws -> Data {
    let size = CGFloat(pixelSize)
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ),
    let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw CocoaError(.fileWriteUnknown)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    defer { NSGraphicsContext.restoreGraphicsState() }

    context.imageInterpolation = .high
    context.shouldAntialias = true

    let outerRect = NSRect(x: 0, y: 0, width: size, height: size)
    let outerPath = NSBezierPath(
        roundedRect: outerRect.insetBy(dx: size * 0.025, dy: size * 0.025),
        xRadius: size * 0.22,
        yRadius: size * 0.22
    )
    let background = NSGradient(
        starting: color(0.94, 0.95, 0.99),
        ending: color(0.79, 0.82, 0.98)
    )
    background?.draw(in: outerPath, angle: -48)

    NSGraphicsContext.saveGraphicsState()
    let tileShadow = NSShadow()
    tileShadow.shadowColor = color(0.22, 0.25, 0.48, 0.18)
    tileShadow.shadowBlurRadius = size * 0.055
    tileShadow.shadowOffset = NSSize(width: 0, height: -size * 0.025)
    tileShadow.set()

    let tileRect = outerRect.insetBy(dx: size * 0.19, dy: size * 0.19)
    let tilePath = NSBezierPath(
        roundedRect: tileRect,
        xRadius: size * 0.145,
        yRadius: size * 0.145
    )
    color(0.97, 0.98, 1, 0.82).setFill()
    tilePath.fill()
    NSGraphicsContext.restoreGraphicsState()

    color(1, 1, 1, 0.56).setStroke()
    tilePath.lineWidth = max(size * 0.009, 0.5)
    tilePath.stroke()

    let barWidth = size * 0.105
    let gap = size * 0.073
    let centerX = size * 0.5
    let bars: [(height: CGFloat, fill: NSColor)] = [
        (size * 0.31, color(0.42, 0.47, 0.91)),
        (size * 0.46, color(0.31, 0.76, 0.66)),
        (size * 0.25, color(0.65, 0.68, 0.97))
    ]

    for (index, bar) in bars.enumerated() {
        let offset = CGFloat(index - 1) * (barWidth + gap)
        let rect = NSRect(
            x: centerX + offset - barWidth / 2,
            y: size * 0.5 - bar.height / 2,
            width: barWidth,
            height: bar.height
        )
        let path = NSBezierPath(
            roundedRect: rect,
            xRadius: barWidth / 2,
            yRadius: barWidth / 2
        )
        bar.fill.setFill()
        path.fill()
    }

    context.flushGraphics()
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return png
}

for output in outputs {
    let data = try renderIcon(pixelSize: output.pixels)
    try data.write(to: destination.appendingPathComponent(output.name), options: .atomic)
}

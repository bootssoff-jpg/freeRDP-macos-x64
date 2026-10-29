#!/usr/bin/env swift
//
// Build the complete macOS iconset and Resources/RDPMac.icns from the approved
// original artwork. The master is a 1254 px PNG; it is downsampled (never
// upscaled) to the 1024 px release master and all required icon sizes.
//
// Usage: swift scripts/make_icon.swift [source.png]
//
import AppKit
import Foundation

let scriptURL = URL(fileURLWithPath: #filePath)
let root = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let sourceURL = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : root.appendingPathComponent("Resources/Branding/rdpmac-icon-arrows-v2.png")
let masterURL = root.appendingPathComponent("Resources/Branding/rdpmac-icon-1024.png")
let iconsetURL = root.appendingPathComponent("Resources/icon.iconset")
let icnsURL = root.appendingPathComponent("Resources/RDPMac.icns")

func fail(_ message: String) -> Never {
    fputs("ERROR: \(message)\n", stderr)
    exit(1)
}

guard let source = NSImage(contentsOf: sourceURL) else {
    fail("cannot read \(sourceURL.path)")
}
guard source.size.width > 0, source.size.height > 0 else {
    fail("source image has no pixels")
}
guard abs(source.size.width - source.size.height) < 1 else {
    fail("source image must be square")
}
guard source.size.width >= 1024 else {
    fail("source image must be at least 1024 px; got \(Int(source.size.width))")
}

func renderPNG(size: Int) -> Data {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                     pixelsWide: size,
                                     pixelsHigh: size,
                                     bitsPerSample: 8,
                                     samplesPerPixel: 4,
                                     hasAlpha: true,
                                     isPlanar: false,
                                     colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0,
                                     bitsPerPixel: 0) else {
        fail("cannot allocate \(size)x\(size) bitmap")
    }
    rep.size = NSSize(width: size, height: size)
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
        fail("cannot create graphics context")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()
    source.draw(in: NSRect(x: 0, y: 0, width: size, height: size),
                from: .zero,
                operation: .sourceOver,
                fraction: 1)
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fail("cannot encode \(size)x\(size) PNG")
    }
    return data
}

try? FileManager.default.removeItem(at: iconsetURL)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png")
]

for (size, name) in sizes {
    try renderPNG(size: size).write(to: iconsetURL.appendingPathComponent(name), options: .atomic)
}
try renderPNG(size: 1024).write(to: masterURL, options: .atomic)

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconsetURL.path, "-o", icnsURL.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    fail("iconutil failed with status \(iconutil.terminationStatus)")
}

print("wrote \(masterURL.path)")
print("wrote \(iconsetURL.path)")
print("wrote \(icnsURL.path)")

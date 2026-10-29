#!/usr/bin/env swift
import AppKit
import CoreGraphics

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else {
    fatalError("no graphics context")
}

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
}

// Rounded dark-blue background.
let background = CGRect(x: 32, y: 32, width: 960, height: 960)
ctx.saveGState()
ctx.addPath(CGPath(roundedRect: background, cornerWidth: 208, cornerHeight: 208,
                   transform: nil))
ctx.clip()
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [color(0x081728), color(0x144A7C)] as CFArray,
                          locations: [0, 1])!
ctx.drawLinearGradient(gradient,
                       start: CGPoint(x: 40, y: 990),
                       end: CGPoint(x: 990, y: 40),
                       options: [])
ctx.restoreGState()

// Subtle rim.
ctx.addPath(CGPath(roundedRect: background.insetBy(dx: 1, dy: 1),
                   cornerWidth: 207, cornerHeight: 207, transform: nil))
ctx.setStrokeColor(color(0xFFFFFF, 0.10))
ctx.setLineWidth(2)
ctx.strokePath()

// Monitor.
let monitor = CGRect(x: 196, y: 342, width: 632, height: 408)
ctx.setFillColor(color(0xF2F7FC))
ctx.addPath(CGPath(roundedRect: monitor, cornerWidth: 38, cornerHeight: 38,
                   transform: nil))
ctx.fillPath()

let screen = monitor.insetBy(dx: 18, dy: 18)
ctx.saveGState()
ctx.addPath(CGPath(roundedRect: screen, cornerWidth: 24, cornerHeight: 24,
                   transform: nil))
ctx.clip()
let screenGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                colors: [color(0x0B2038), color(0x15507F)] as CFArray,
                                locations: [0, 1])!
ctx.drawLinearGradient(screenGradient,
                       start: CGPoint(x: screen.minX, y: screen.maxY),
                       end: CGPoint(x: screen.maxX, y: screen.minY),
                       options: [])
ctx.restoreGState()

// Monitor stand and base.
ctx.setFillColor(color(0xDCE8F4))
ctx.addPath(CGPath(roundedRect: CGRect(x: 466, y: 300, width: 92, height: 46),
                   cornerWidth: 14, cornerHeight: 14, transform: nil))
ctx.fillPath()
ctx.addPath(CGPath(roundedRect: CGRect(x: 378, y: 252, width: 268, height: 26),
                   cornerWidth: 13, cornerHeight: 13, transform: nil))
ctx.fillPath()

// Clipboard: back sheet, front sheet, clip and text lines.
let backSheet = CGRect(x: 414, y: 438, width: 196, height: 224)
ctx.setFillColor(color(0x9FC3E2, 0.55))
ctx.addPath(CGPath(roundedRect: backSheet, cornerWidth: 24, cornerHeight: 24,
                   transform: nil))
ctx.fillPath()

let frontSheet = CGRect(x: 446, y: 466, width: 196, height: 224)
ctx.setFillColor(color(0xFFFFFF))
ctx.addPath(CGPath(roundedRect: frontSheet, cornerWidth: 24, cornerHeight: 24,
                   transform: nil))
ctx.fillPath()
ctx.addPath(CGPath(roundedRect: frontSheet, cornerWidth: 24, cornerHeight: 24,
                   transform: nil))
ctx.setStrokeColor(color(0x0C2C4A, 0.10))
ctx.setLineWidth(3)
ctx.strokePath()

let clip = CGRect(x: 500, y: 664, width: 88, height: 30)
ctx.setFillColor(color(0x1F7A4D))
ctx.addPath(CGPath(roundedRect: clip, cornerWidth: 14, cornerHeight: 14,
                   transform: nil))
ctx.fillPath()

ctx.setFillColor(color(0x1A4E78, 0.82))
for (index, width) in [132, 116, 140].enumerated() {
    let y = 606 - CGFloat(index) * 48
    ctx.addPath(CGPath(roundedRect: CGRect(x: 476, y: y, width: CGFloat(width),
                                           height: 18),
                       cornerWidth: 9, cornerHeight: 9, transform: nil))
    ctx.fillPath()
}

// Small connection indicator.
ctx.setFillColor(color(0x35D07F))
ctx.fillEllipse(in: CGRect(x: 770, y: 292, width: 34, height: 34))
ctx.setStrokeColor(color(0x0A1B2C))
ctx.setLineWidth(6)
ctx.strokeEllipse(in: CGRect(x: 770, y: 292, width: 34, height: 34))

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("PNG encoding failed")
}
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
try png.write(to: URL(fileURLWithPath: output))
print("wrote \(output)")

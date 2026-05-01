#!/usr/bin/env swift
// Generates the ParamClaudeBar app icon at all required sizes.
// Usage: swift macos/scripts/generate-app-icon.swift
//
// Writes PNGs into Resources/Assets.xcassets/AppIcon.appiconset/ and a
// fresh Resources/AppIcon.icns built via iconutil.

import AppKit
import Foundation

let projectDir = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath
)
let resourcesDir = projectDir.appendingPathComponent("macos/Resources")
let appiconsetDir = resourcesDir
    .appendingPathComponent("Assets.xcassets/AppIcon.appiconset")
let icnsPath = resourcesDir.appendingPathComponent("AppIcon.icns")

// MARK: - Drawing

private func drawIcon(into size: NSSize) -> NSImage {
    return NSImage(size: size, flipped: false) { rect in
        let ctx = NSGraphicsContext.current!.cgContext
        let s = rect.width

        // Squircle clip — corner radius ≈ 22.4% of width to approximate
        // Apple's macOS Big Sur+ rounded-square mask.
        let cornerRadius = s * 0.224
        let squircle = NSBezierPath(
            roundedRect: rect,
            xRadius: cornerRadius,
            yRadius: cornerRadius
        )
        squircle.addClip()

        // Background gradient — deep indigo at the top fading into a
        // warmer plum at the bottom. Both colours sit comfortably in the
        // §7.3 7-day palette space (blue → purple).
        let bgTop = NSColor(srgbRed: 0.13, green: 0.10, blue: 0.27, alpha: 1.0)
        let bgBottom = NSColor(srgbRed: 0.34, green: 0.20, blue: 0.49, alpha: 1.0)
        let gradient = NSGradient(starting: bgTop, ending: bgBottom)
        gradient?.draw(in: rect, angle: -90)

        // Top-edge highlight, very subtle.
        let highlight = NSGradient(colors: [
            NSColor.white.withAlphaComponent(0.10),
            NSColor.white.withAlphaComponent(0.0),
        ])
        highlight?.draw(
            in: NSRect(x: 0, y: rect.height * 0.55, width: rect.width, height: rect.height * 0.45),
            angle: -90
        )

        let center = NSPoint(x: rect.midX, y: rect.midY)

        // Outer ring (7-day) — coral.
        let outerRadius = s * 0.34
        let outerStroke = s * 0.062
        drawRing(
            center: center,
            radius: outerRadius,
            stroke: outerStroke,
            color: NSColor(srgbRed: 1.00, green: 0.49, blue: 0.36, alpha: 1.0)
        )

        // Inner ring (5-hour) — sky.
        let innerRadius = s * 0.21
        let innerStroke = s * 0.052
        drawRing(
            center: center,
            radius: innerRadius,
            stroke: innerStroke,
            color: NSColor(srgbRed: 0.50, green: 0.83, blue: 0.99, alpha: 1.0)
        )

        // Center dot — tiny anchor that pulls the eye to the middle and
        // suggests "gauge" rather than "ring stack".
        let dotRadius = s * 0.025
        let dotRect = NSRect(
            x: center.x - dotRadius,
            y: center.y - dotRadius,
            width: dotRadius * 2,
            height: dotRadius * 2
        )
        NSColor(srgbRed: 0.96, green: 0.97, blue: 1.00, alpha: 1.0).setFill()
        NSBezierPath(ovalIn: dotRect).fill()

        _ = ctx
        return true
    }
}

private func drawRing(
    center: NSPoint,
    radius: CGFloat,
    stroke: CGFloat,
    color: NSColor
) {
    // Faint background ring at 18% so the colour reads even in light
    // contexts where the rendered icon thumbnails get small.
    let bg = NSBezierPath()
    bg.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
    bg.lineWidth = stroke
    color.withAlphaComponent(0.18).setStroke()
    bg.stroke()

    // Foreground ring — solid colour, full circle.
    let fg = NSBezierPath()
    fg.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
    fg.lineWidth = stroke
    fg.lineCapStyle = .round
    color.setStroke()
    fg.stroke()
}

// MARK: - Saving

private func resampled(_ source: NSImage, to size: NSSize) -> NSImage {
    let target = NSImage(size: size)
    target.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    source.draw(
        in: NSRect(origin: .zero, size: size),
        from: NSRect(origin: .zero, size: source.size),
        operation: .copy,
        fraction: 1.0
    )
    target.unlockFocus()
    return target
}

private func savePNG(_ image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "GenerateIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode \(url.lastPathComponent)"])
    }
    try data.write(to: url, options: .atomic)
}

// MARK: - Main

let masterSize = NSSize(width: 1024, height: 1024)
let master = drawIcon(into: masterSize)

let appiconsetTargets: [(String, CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for (filename, dimension) in appiconsetTargets {
    let url = appiconsetDir.appendingPathComponent(filename)
    let scaled = resampled(master, to: NSSize(width: dimension, height: dimension))
    try savePNG(scaled, to: url)
    FileHandle.standardOutput.write(Data("wrote \(filename)\n".utf8))
}

// Build .iconset directory in tmp, then iconutil -> AppIcon.icns.
let tmp = FileManager.default.temporaryDirectory
    .appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: tmp) }

let iconsetTargets: [(String, CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]
for (filename, dimension) in iconsetTargets {
    let url = tmp.appendingPathComponent(filename)
    let scaled = resampled(master, to: NSSize(width: dimension, height: dimension))
    try savePNG(scaled, to: url)
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", "-o", icnsPath.path, tmp.path]
try task.run()
task.waitUntilExit()
if task.terminationStatus != 0 {
    FileHandle.standardError.write(Data("iconutil failed with status \(task.terminationStatus)\n".utf8))
    exit(Int32(task.terminationStatus))
}
FileHandle.standardOutput.write(Data("wrote \(icnsPath.path)\n".utf8))

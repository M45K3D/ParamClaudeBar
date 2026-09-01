import AppKit

// 22×22pt menu-bar icon: a single progress ring wrapped around the Claude
// asterisk. The ring tracks whichever metric the user selected for the menu bar
// (5-hour window or session context) and sweeps clockwise from 12 o'clock over
// a 10% label-colour track. Rendered as a non-template image so the severity
// colour survives; the monochrome variant is a template image so macOS can
// invert it on selection.

private let iconSize: CGFloat = 22
private let ringStroke: CGFloat = 2.5
private let ringRadius: CGFloat = (iconSize - ringStroke) / 2 - 0.5
private let logoBoxSize: CGFloat = 10.5
private let iconCenter = NSPoint(x: iconSize / 2, y: iconSize / 2)

func renderIcon(fraction: Double, monochrome: Bool = false) -> NSImage {
    makeIcon(fraction: clampFraction(fraction), monochrome: monochrome)
}

func renderUnauthenticatedIcon(monochrome: Bool = false) -> NSImage {
    makeIcon(fraction: 0, monochrome: monochrome)
}

// MARK: - Drawing

private func makeIcon(fraction: Double, monochrome: Bool) -> NSImage {
    let size = NSSize(width: iconSize, height: iconSize)
    let image = NSImage(size: size, flipped: false) { _ in
        drawRing(
            fraction: fraction,
            arcColor: monochrome ? .labelColor : ringColor(fraction: fraction)
        )
        drawLogo()
        return true
    }
    image.isTemplate = monochrome
    return image
}

private func drawRing(fraction: Double, arcColor: NSColor) {
    let track = NSBezierPath()
    track.appendArc(
        withCenter: iconCenter,
        radius: ringRadius,
        startAngle: 0,
        endAngle: 360,
        clockwise: false
    )
    track.lineWidth = ringStroke
    NSColor.labelColor.withAlphaComponent(0.1).setStroke()
    track.stroke()

    guard fraction > 0 else { return }

    let arc = NSBezierPath()
    arc.appendArc(
        withCenter: iconCenter,
        radius: ringRadius,
        startAngle: 90,
        endAngle: 90 - fraction * 360,
        clockwise: true
    )
    arc.lineWidth = ringStroke
    arc.lineCapStyle = .round
    arcColor.setStroke()
    arc.stroke()
}

private func drawLogo() {
    let box = NSRect(
        x: (iconSize - logoBoxSize) / 2,
        y: (iconSize - logoBoxSize) / 2,
        width: logoBoxSize,
        height: logoBoxSize
    )
    // The artwork is authored y-down, so flip it inside the icon box to draw
    // upright in AppKit's y-up context.
    let path = ClaudeLogo.fittedPathFlipped(in: box, boxHeight: iconSize)
    NSColor.labelColor.setFill()
    NSBezierPath(cgPath: path).fill()
}

// MARK: - Colour thresholds (SPEC §7.3)

private func ringColor(fraction: Double) -> NSColor {
    switch fraction {
    case ..<0.60: return .systemGreen
    case 0.60..<0.85: return .systemOrange
    default: return .systemRed
    }
}

private func clampFraction(_ value: Double) -> Double {
    max(0, min(1, value))
}

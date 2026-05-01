import AppKit

// 22×22pt menu-bar icon with two concentric ring gauges, per SPEC §7.2 / §7.3.
// The outer ring tracks the 7-day window; the inner ring tracks the 5-hour
// window. Each ring is drawn over a 10% label-colour background ring, then
// the coloured arc sweeps clockwise from 12 o'clock proportional to its
// fraction. The icon is rendered as a non-template image so the system
// colours come through unchanged.

private let iconSize: CGFloat = 22
private let outerStroke: CGFloat = 3
private let innerStroke: CGFloat = 2
private let innerInsetFromOuterEdge: CGFloat = 4

private let outerRadius: CGFloat = (iconSize - outerStroke) / 2
private let innerBoundsInset = innerInsetFromOuterEdge
private let innerRadius: CGFloat =
    (iconSize - 2 * innerBoundsInset - innerStroke) / 2
private let iconCenter = NSPoint(x: iconSize / 2, y: iconSize / 2)

func renderIcon(pct5h: Double, pct7d: Double) -> NSImage {
    makeIcon(frac5h: clampFraction(pct5h), frac7d: clampFraction(pct7d))
}

func renderUnauthenticatedIcon() -> NSImage {
    makeIcon(frac5h: 0, frac7d: 0)
}

// MARK: - Drawing

private func makeIcon(frac5h: Double, frac7d: Double) -> NSImage {
    let size = NSSize(width: iconSize, height: iconSize)
    let image = NSImage(size: size, flipped: false) { _ in
        drawRing(
            radius: outerRadius,
            fraction: frac7d,
            stroke: outerStroke,
            arcColor: sevenDayRingColor(fraction: frac7d)
        )
        drawRing(
            radius: innerRadius,
            fraction: frac5h,
            stroke: innerStroke,
            arcColor: fiveHourRingColor(fraction: frac5h)
        )
        return true
    }
    image.isTemplate = false
    return image
}

private func drawRing(
    radius: CGFloat,
    fraction: Double,
    stroke: CGFloat,
    arcColor: NSColor
) {
    let background = NSBezierPath()
    background.appendArc(
        withCenter: iconCenter,
        radius: radius,
        startAngle: 0,
        endAngle: 360,
        clockwise: false
    )
    background.lineWidth = stroke
    NSColor.labelColor.withAlphaComponent(0.1).setStroke()
    background.stroke()

    guard fraction > 0 else { return }

    let sweepDegrees = fraction * 360
    let arc = NSBezierPath()
    arc.appendArc(
        withCenter: iconCenter,
        radius: radius,
        startAngle: 90,
        endAngle: 90 - sweepDegrees,
        clockwise: true
    )
    arc.lineWidth = stroke
    arc.lineCapStyle = .round
    arcColor.setStroke()
    arc.stroke()
}

// MARK: - Colour thresholds (SPEC §7.3)

private func fiveHourRingColor(fraction: Double) -> NSColor {
    switch fraction {
    case ..<0.60: return .systemGreen
    case 0.60..<0.85: return .systemOrange
    default: return .systemRed
    }
}

private func sevenDayRingColor(fraction: Double) -> NSColor {
    switch fraction {
    case ..<0.60: return .systemBlue
    case 0.60..<0.85: return .systemPurple
    default: return .systemPink
    }
}

private func clampFraction(_ value: Double) -> Double {
    max(0, min(1, value))
}

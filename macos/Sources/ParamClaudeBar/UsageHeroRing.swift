import SwiftUI

/// Hero dual-ring gauge used at the top of the popover. Mirrors the menu
/// bar icon (outer = 7-day, inner = 5-hour) but scaled up so it can
/// anchor the popover's visual identity. Pure SwiftUI shapes so the
/// arcs animate smoothly between data updates.
struct UsageHeroRing: View {
    let fraction5h: Double
    let fraction7d: Double
    var size: CGFloat = 120
    var outerStroke: CGFloat = 10
    var innerStroke: CGFloat = 8
    var ringGap: CGFloat = 6

    private var outerRadius: CGFloat { (size - outerStroke) / 2 }
    private var innerRadius: CGFloat {
        outerRadius - outerStroke / 2 - ringGap - innerStroke / 2
    }

    private var dominantPercent: Int {
        Int(round(max(fraction5h, fraction7d) * 100))
    }

    var body: some View {
        ZStack {
            ringPair(
                radius: outerRadius,
                stroke: outerStroke,
                fraction: fraction7d,
                color: Theme.sevenDayTint(forFraction: fraction7d)
            )
            ringPair(
                radius: innerRadius,
                stroke: innerStroke,
                fraction: fraction5h,
                color: Theme.fiveHourTint(forFraction: fraction5h)
            )
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(dominantPercent)")
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("%")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .animation(.easeInOut(duration: 0.25), value: fraction5h)
        .animation(.easeInOut(duration: 0.25), value: fraction7d)
    }

    @ViewBuilder
    private func ringPair(
        radius: CGFloat,
        stroke: CGFloat,
        fraction: Double,
        color: Color
    ) -> some View {
        ZStack {
            Circle()
                .stroke(
                    Color.secondary.opacity(0.18),
                    style: StrokeStyle(lineWidth: stroke, lineCap: .round)
                )
                .frame(width: radius * 2, height: radius * 2)
            ArcShape(fraction: fraction)
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: stroke, lineCap: .round)
                )
                .frame(width: radius * 2, height: radius * 2)
        }
    }
}

private struct ArcShape: Shape {
    var fraction: Double

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let f = max(0, min(1, fraction))
        guard f > 0 else { return path }

        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2

        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(-90),
            endAngle: .degrees(-90 + 360 * f),
            clockwise: false
        )
        return path
    }
}

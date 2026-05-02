import SwiftUI
import Charts

struct UsageChartView: View {
    @ObservedObject var historyService: UsageHistoryService

    private let range: TimeRange = .day1

    var body: some View {
        let points = historyService.downsampledPoints(for: range)

        HStack(alignment: .center, spacing: 10) {
            if points.isEmpty {
                emptyState
            } else {
                chartView(points: points)
                legend
            }
        }
        .frame(height: 50)
    }

    @ViewBuilder
    private var emptyState: some View {
        Text("Collecting usage history…")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private func chartView(points: [UsageDataPoint]) -> some View {
        Chart {
            ForEach(points) { point in
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Usage", point.pct5h * 100),
                    series: .value("Window", "5h")
                )
                .foregroundStyle(by: .value("Window", "5h"))
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.catmullRom)
            }

            ForEach(points) { point in
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Usage", point.pct7d * 100),
                    series: .value("Window", "7d")
                )
                .foregroundStyle(by: .value("Window", "7d"))
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.catmullRom)
            }
        }
        .chartForegroundStyleScale([
            "5h": Theme.fiveHourAccent,
            "7d": Theme.sevenDayAccent
        ])
        .chartXScale(domain: Date.now.addingTimeInterval(-range.interval)...Date.now)
        .chartYScale(domain: 0...100)
        .chartYAxis(.hidden)
        .chartXAxis(.hidden)
        .chartLegend(.hidden)
        .chartPlotStyle { plot in plot.clipped() }
        .frame(maxWidth: .infinity)
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 4) {
            LegendDot(color: Theme.fiveHourAccent, label: "5h")
            LegendDot(color: Theme.sevenDayAccent, label: "7d")
        }
        .font(.system(size: 9))
    }
}

private struct LegendDot: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(label)
                .foregroundStyle(.secondary)
        }
    }
}

struct UsageChartInterpolatedValues {
    let date: Date
    let pct5h: Double
    let pct7d: Double
}

enum UsageChartInterpolation {
    static func catmullRom(_ p0: Double, _ p1: Double, _ p2: Double, _ p3: Double, t: Double) -> Double {
        let t2 = t * t
        let t3 = t2 * t
        return 0.5 * (
            (2 * p1) +
            (-p0 + p2) * t +
            (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 +
            (-p0 + 3 * p1 - 3 * p2 + p3) * t3
        )
    }

    static func interpolateValues(at date: Date, in points: [UsageDataPoint]) -> UsageChartInterpolatedValues? {
        guard points.count >= 2 else { return nil }

        let sorted = points.sorted { $0.timestamp < $1.timestamp }

        if date < sorted.first!.timestamp || date > sorted.last!.timestamp {
            return UsageChartInterpolatedValues(date: date, pct5h: 0, pct7d: 0)
        }

        for i in 0..<(sorted.count - 1) {
            if date >= sorted[i].timestamp && date <= sorted[i + 1].timestamp {
                let span = sorted[i + 1].timestamp.timeIntervalSince(sorted[i].timestamp)
                let t = span > 0 ? date.timeIntervalSince(sorted[i].timestamp) / span : 0

                let i0 = max(0, i - 1)
                let i3 = min(sorted.count - 1, i + 2)

                let pct5h = catmullRom(
                    sorted[i0].pct5h, sorted[i].pct5h,
                    sorted[i + 1].pct5h, sorted[i3].pct5h, t: t
                )
                let pct7d = catmullRom(
                    sorted[i0].pct7d, sorted[i].pct7d,
                    sorted[i + 1].pct7d, sorted[i3].pct7d, t: t
                )

                return UsageChartInterpolatedValues(
                    date: date,
                    pct5h: clampToUnitInterval(pct5h),
                    pct7d: clampToUnitInterval(pct7d)
                )
            }
        }

        return nil
    }

    private static func clampToUnitInterval(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

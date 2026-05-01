import SwiftUI
import Charts

struct UsageChartView: View {
    @ObservedObject var historyService: UsageHistoryService
    @State private var selectedRange: TimeRange = .day1
    @State private var hoverDate: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("", selection: $selectedRange) {
                ForEach(TimeRange.allCases) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            let points = historyService.downsampledPoints(for: selectedRange)

            if points.isEmpty {
                emptyState
            } else {
                chartView(points: points)
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        Text("Collecting usage history… check back in a few minutes")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 140, alignment: .center)
            .multilineTextAlignment(.center)
    }

    @ViewBuilder
    private func chartView(points: [UsageDataPoint]) -> some View {
        let interpolated = hoverDate.flatMap {
            UsageChartInterpolation.interpolateValues(at: $0, in: points)
        }

        Chart {
            // 5-hour: filled accent area with a line on top
            ForEach(points) { point in
                AreaMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Usage", point.pct5h * 100)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Theme.fiveHourAccent.opacity(0.30),
                            Theme.fiveHourAccent.opacity(0.05)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)
            }

            ForEach(points) { point in
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Usage", point.pct5h * 100)
                )
                .foregroundStyle(by: .value("Window", "5h"))
                .interpolationMethod(.catmullRom)
            }

            // 7-day: line only
            ForEach(points) { point in
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Usage", point.pct7d * 100)
                )
                .foregroundStyle(by: .value("Window", "7d"))
                .interpolationMethod(.catmullRom)
            }

            if let iv = interpolated {
                RuleMark(x: .value("Selected", iv.date))
                    .foregroundStyle(.secondary.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1))

                PointMark(
                    x: .value("Time", iv.date),
                    y: .value("Usage", iv.pct5h * 100)
                )
                .foregroundStyle(Theme.fiveHourAccent)
                .symbolSize(28)

                PointMark(
                    x: .value("Time", iv.date),
                    y: .value("Usage", iv.pct7d * 100)
                )
                .foregroundStyle(Theme.sevenDayAccent)
                .symbolSize(28)
            }
        }
        .chartXScale(domain: Date.now.addingTimeInterval(-selectedRange.interval)...Date.now)
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(values: [25, 50, 75, 100]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                    .foregroundStyle(.secondary.opacity(0.4))
                AxisValueLabel {
                    if let v = value.as(Int.self) {
                        Text("\(v)%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: xAxisDesiredCount)) { _ in
                AxisValueLabel(format: xAxisFormat)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .chartForegroundStyleScale([
            "5h": Theme.fiveHourAccent,
            "7d": Theme.sevenDayAccent
        ])
        .chartLegend(position: .bottom, spacing: 4) {
            HStack(spacing: 12) {
                LegendDot(color: Theme.fiveHourAccent, label: "5h")
                LegendDot(color: Theme.sevenDayAccent, label: "7d")
            }
            .font(.caption2)
        }
        .chartPlotStyle { plot in
            plot.clipped()
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            let plotOrigin = geo[proxy.plotFrame!].origin
                            let x = location.x - plotOrigin.x
                            if let date: Date = proxy.value(atX: x) {
                                hoverDate = date
                            }
                        case .ended:
                            hoverDate = nil
                        }
                    }
            }
        }
        .overlay(alignment: .top) {
            if let iv = interpolated {
                tooltipView(date: iv.date, pct5h: iv.pct5h, pct7d: iv.pct7d)
            }
        }
        .frame(height: 140)
        .padding(.top, 4)
    }

    @ViewBuilder
    private func tooltipView(date: Date, pct5h: Double, pct7d: Double) -> some View {
        VStack(spacing: 2) {
            Text(date, format: tooltipDateFormat)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            HStack(spacing: 8) {
                Label("\(Int(round(pct5h * 100)))%", systemImage: "circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.fiveHourAccent)
                Label("\(Int(round(pct7d * 100)))%", systemImage: "circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.sevenDayAccent)
            }
            .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Formatting

    private var xAxisFormat: Date.FormatStyle {
        switch selectedRange {
        case .hour1, .hour6, .day1:
            return .dateTime.hour().minute().locale(.init(identifier: "en_GB"))
        case .day7, .day30:
            return .dateTime.day().month(.abbreviated).locale(.init(identifier: "en_GB"))
        }
    }

    private var xAxisDesiredCount: Int {
        switch selectedRange {
        case .hour1, .hour6: return 4
        case .day1: return 5
        case .day7: return 4
        case .day30: return 5
        }
    }

    private var tooltipDateFormat: Date.FormatStyle {
        let locale = Locale(identifier: "en_GB")
        switch selectedRange {
        case .hour1, .hour6, .day1:
            return .dateTime.hour().minute().locale(locale)
        case .day7:
            return .dateTime.weekday(.abbreviated).hour().minute().locale(locale)
        case .day30:
            return .dateTime.month(.abbreviated).day().hour().locale(locale)
        }
    }
}

private struct LegendDot: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
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

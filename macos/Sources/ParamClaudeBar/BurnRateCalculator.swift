import Foundation

/// Result of a burn-rate projection per SPEC §11.
struct BurnRateProjection: Equatable {
    /// Linear-regression slope expressed as percentage points per hour.
    /// Negative values mean usage is decreasing (recovering); zero means idle.
    let burnRatePerHour: Double

    /// Time at which the window is projected to hit 100%, or `nil` if:
    ///   – history is too sparse to fit a slope
    ///   – the slope is ≤ 0 (idle / recovering)
    ///   – the projected hit time is past the window's reset (on track)
    let projectedHitTime: Date?
}

/// Pure burn-rate projection used to populate the Insights row (§8.3).
///
/// Implements the algorithm from SPEC §11:
/// 1. Take the last `windowMinutes` of history (or all if fewer points).
/// 2. Linear regression on (time, percentage). Slope → % per hour.
/// 3. If slope ≤ 0 → projection = nil ("Idle" / "Recovering").
/// 4. Else: timeToHit = (100 - currentPercent) / slope; projectedHitTime = now + timeToHit.
/// 5. If projectedHitTime > resetTime → projection = nil ("On track").
/// 6. Else → projection = projectedHitTime.
enum BurnRateCalculator {
    /// - Parameters:
    ///   - points: usage history points; `valueExtractor` chooses which series.
    ///   - valueExtractor: returns the series value as a 0–100 percentage.
    ///   - currentPercent: the current value of the same series, 0–100.
    ///   - resetTime: window reset time, or `nil` when unknown.
    ///   - now: clock injection for tests; defaults to `Date()`.
    ///   - windowMinutes: regression window in minutes; defaults to 30 per §11.
    static func project(
        points: [UsageDataPoint],
        valueExtractor: (UsageDataPoint) -> Double,
        currentPercent: Double,
        resetTime: Date?,
        now: Date = Date(),
        windowMinutes: Int = 30
    ) -> BurnRateProjection {
        let cutoff = now.addingTimeInterval(-Double(windowMinutes) * 60)
        let recent = points
            .filter { $0.timestamp >= cutoff && $0.timestamp <= now }
            .sorted { $0.timestamp < $1.timestamp }

        guard recent.count >= 2 else {
            return BurnRateProjection(burnRatePerHour: 0, projectedHitTime: nil)
        }

        let slopePerSecond = linearRegressionSlope(
            recent: recent,
            valueExtractor: valueExtractor
        )
        let slopePerHour = slopePerSecond * 3600

        guard slopePerHour > 0 else {
            return BurnRateProjection(burnRatePerHour: slopePerHour, projectedHitTime: nil)
        }

        let remaining = max(0, 100 - currentPercent)
        let secondsToHit = remaining / slopePerHour * 3600
        let projectedHit = now.addingTimeInterval(secondsToHit)

        if let resetTime, projectedHit > resetTime {
            return BurnRateProjection(burnRatePerHour: slopePerHour, projectedHitTime: nil)
        }

        return BurnRateProjection(
            burnRatePerHour: slopePerHour,
            projectedHitTime: projectedHit
        )
    }

    private static func linearRegressionSlope(
        recent: [UsageDataPoint],
        valueExtractor: (UsageDataPoint) -> Double
    ) -> Double {
        let n = Double(recent.count)
        let xs = recent.map { $0.timestamp.timeIntervalSince1970 }
        let ys = recent.map { valueExtractor($0) }

        let meanX = xs.reduce(0, +) / n
        let meanY = ys.reduce(0, +) / n

        var numerator = 0.0
        var denominator = 0.0
        for i in 0..<recent.count {
            let dx = xs[i] - meanX
            numerator += dx * (ys[i] - meanY)
            denominator += dx * dx
        }
        guard denominator > 0 else { return 0 }
        return numerator / denominator
    }
}

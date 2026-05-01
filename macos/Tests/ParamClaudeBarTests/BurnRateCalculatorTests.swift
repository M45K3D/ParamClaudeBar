import XCTest
@testable import ParamClaudeBar

final class BurnRateCalculatorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_770_000_000)

    func testTooFewPointsReportsIdle() {
        let result = BurnRateCalculator.project(
            points: [],
            valueExtractor: { $0.pct5h * 100 },
            currentPercent: 30,
            resetTime: now.addingTimeInterval(3600),
            now: now
        )
        XCTAssertEqual(result, BurnRateProjection(burnRatePerHour: 0, projectedHitTime: nil))
    }

    func testNegativeSlopeReportsRecovering() {
        let points = [
            UsageDataPoint(timestamp: now.addingTimeInterval(-1500), pct5h: 0.50, pct7d: 0),
            UsageDataPoint(timestamp: now.addingTimeInterval(-1000), pct5h: 0.45, pct7d: 0),
            UsageDataPoint(timestamp: now.addingTimeInterval(-500), pct5h: 0.40, pct7d: 0)
        ]
        let result = BurnRateCalculator.project(
            points: points,
            valueExtractor: { $0.pct5h * 100 },
            currentPercent: 40,
            resetTime: now.addingTimeInterval(3600),
            now: now
        )
        XCTAssertLessThan(result.burnRatePerHour, 0)
        XCTAssertNil(result.projectedHitTime)
    }

    func testProjectionAtSteadyClimb() {
        // 0% → 30% over 30 min = 60% per hour.
        let points = (0...6).map { i -> UsageDataPoint in
            let t = now.addingTimeInterval(-Double(30 - i * 5) * 60)
            return UsageDataPoint(timestamp: t, pct5h: Double(i) * 5 / 100, pct7d: 0)
        }
        let result = BurnRateCalculator.project(
            points: points,
            valueExtractor: { $0.pct5h * 100 },
            currentPercent: 30,
            resetTime: now.addingTimeInterval(7200),  // 2h until reset
            now: now
        )
        // Slope was 5%/5min == 60%/h. Remaining = 70%. Time to hit ≈ 70 / 60 hours ≈ 70min.
        XCTAssertEqual(result.burnRatePerHour, 60, accuracy: 0.5)
        let expected = now.addingTimeInterval(70.0 / 60.0 * 3600)
        XCTAssertNotNil(result.projectedHitTime)
        XCTAssertEqual(result.projectedHitTime!.timeIntervalSinceReferenceDate,
                       expected.timeIntervalSinceReferenceDate, accuracy: 60)
    }

    func testProjectionPastResetReportsOnTrack() {
        // Slow climb of 5%/h → would take 14 hours to fill, but reset in 1h.
        let points = [
            UsageDataPoint(timestamp: now.addingTimeInterval(-1800), pct5h: 0.27, pct7d: 0),
            UsageDataPoint(timestamp: now.addingTimeInterval(-1200), pct5h: 0.28, pct7d: 0),
            UsageDataPoint(timestamp: now.addingTimeInterval(-600), pct5h: 0.29, pct7d: 0),
            UsageDataPoint(timestamp: now, pct5h: 0.30, pct7d: 0)
        ]
        let result = BurnRateCalculator.project(
            points: points,
            valueExtractor: { $0.pct5h * 100 },
            currentPercent: 30,
            resetTime: now.addingTimeInterval(3600),
            now: now
        )
        XCTAssertGreaterThan(result.burnRatePerHour, 0)
        XCTAssertNil(result.projectedHitTime)
    }

    func testIgnoresPointsOutsideRegressionWindow() {
        // Old points showing huge climb shouldn't influence the slope.
        let points = [
            UsageDataPoint(timestamp: now.addingTimeInterval(-86400), pct5h: 0.0, pct7d: 0),
            UsageDataPoint(timestamp: now.addingTimeInterval(-43200), pct5h: 0.99, pct7d: 0),
            UsageDataPoint(timestamp: now.addingTimeInterval(-1500), pct5h: 0.30, pct7d: 0),
            UsageDataPoint(timestamp: now.addingTimeInterval(-1000), pct5h: 0.31, pct7d: 0),
            UsageDataPoint(timestamp: now.addingTimeInterval(-500), pct5h: 0.32, pct7d: 0)
        ]
        let result = BurnRateCalculator.project(
            points: points,
            valueExtractor: { $0.pct5h * 100 },
            currentPercent: 32,
            resetTime: now.addingTimeInterval(7200),
            now: now,
            windowMinutes: 30
        )
        // Last 30min: 30% → 32% over 1000s ≈ 7.2%/h.
        XCTAssertEqual(result.burnRatePerHour, 7.2, accuracy: 0.5)
    }
}

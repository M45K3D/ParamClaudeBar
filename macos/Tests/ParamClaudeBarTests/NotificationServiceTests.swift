import XCTest
@testable import ParamClaudeBar

final class NotificationServiceTests: XCTestCase {
    func testNoCrossesWhenAllOff() {
        let alerts = threshholdCrosses(
            warningEnabled: false,
            criticalEnabled: false,
            warningPercent: 75,
            criticalPercent: 90,
            pct5h: 80,
            pct7d: 80
        )
        XCTAssertTrue(alerts.isEmpty)
    }

    func testWarningFiresForBothWindows() {
        let alerts = threshholdCrosses(
            warningEnabled: true,
            criticalEnabled: false,
            warningPercent: 75,
            criticalPercent: 90,
            pct5h: 76,
            pct7d: 75
        )
        XCTAssertEqual(alerts, [
            ThresholdCross(window: "5h", kind: "warning", pct: 76),
            ThresholdCross(window: "7d", kind: "warning", pct: 75)
        ])
    }

    func testCriticalFiresAndIncludesWarningStillBelow() {
        let alerts = threshholdCrosses(
            warningEnabled: true,
            criticalEnabled: true,
            warningPercent: 75,
            criticalPercent: 90,
            pct5h: 92,
            pct7d: 70
        )
        XCTAssertEqual(alerts, [
            ThresholdCross(window: "5h", kind: "warning", pct: 92),
            ThresholdCross(window: "5h", kind: "critical", pct: 92)
        ])
    }

    func testNothingFiresBelowThresholds() {
        let alerts = threshholdCrosses(
            warningEnabled: true,
            criticalEnabled: true,
            warningPercent: 75,
            criticalPercent: 90,
            pct5h: 50,
            pct7d: 60
        )
        XCTAssertTrue(alerts.isEmpty)
    }

    // Integration-ish: make sure debounce state survives one evaluate(...)
    // call, by exercising a fresh suite-scoped UserDefaults instance.
    func testEvaluateDoesNotCrashAndPersistsDebounceState() {
        let defaultsName = "ParamClaudeBar.Tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defer {
            defaults.removePersistentDomain(forName: defaultsName)
        }
        let service = MainActor.assumeIsolated {
            NotificationService(defaults: defaults)
        }
        MainActor.assumeIsolated {
            service.warningEnabled = true
            service.warningPercent = 75
            service.criticalEnabled = false
            service.burnRateEnabled = false
            service.resetEnabled = false
            service.evaluate(
                pct5h: 80,
                pct7d: 50,
                reset5h: Date().addingTimeInterval(3600),
                reset7d: Date().addingTimeInterval(7 * 86400),
                burnRate5h: nil
            )
        }
        // After evaluate, debounce keys for 5h warning should be present.
        XCTAssertNotNil(defaults.string(forKey: "notify.last.warning.5h"))
    }
}

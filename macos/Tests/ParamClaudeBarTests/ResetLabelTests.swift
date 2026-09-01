import XCTest
@testable import ParamClaudeBar

final class ResetLabelTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func label(inMinutes minutes: Double) -> String {
        resetLabel(for: now.addingTimeInterval(minutes * 60), now: now)
    }

    func testCountdownInMinutes() {
        XCTAssertEqual(label(inMinutes: 51), "Resets in 51 min")
        XCTAssertEqual(label(inMinutes: 1), "Resets in 1 min")
        XCTAssertEqual(label(inMinutes: 59), "Resets in 59 min")
    }

    func testCountdownInHours() {
        XCTAssertEqual(label(inMinutes: 60), "Resets in 1 hr")
        XCTAssertEqual(label(inMinutes: 135), "Resets in 2 hr 15 min")
        XCTAssertEqual(label(inMinutes: 240), "Resets in 4 hr")
    }

    func testSubMinuteAndElapsed() {
        XCTAssertEqual(label(inMinutes: 0.5), "Resets in <1 min")
        XCTAssertEqual(label(inMinutes: -5), "Resetting…")
        XCTAssertEqual(label(inMinutes: 0), "Resetting…")
    }

    func testFarOutSwitchesToAbsoluteDayAndTime() {
        // Beyond 12 hours the countdown gives way to a weekday + clock time.
        let result = label(inMinutes: 60 * 24 * 3)
        XCTAssertTrue(result.hasPrefix("Resets "), result)
        XCTAssertFalse(result.contains("in "), result)
        // Weekday abbreviation should be present for a different day.
        XCTAssertGreaterThan(result.count, "Resets ".count + 5, result)
    }

    func testBoundaryAtTwelveHours() {
        XCTAssertEqual(label(inMinutes: 60 * 11), "Resets in 11 hr")
        // At 12h exactly we switch to the absolute form.
        XCTAssertFalse(label(inMinutes: 60 * 12).contains("in "))
    }
}

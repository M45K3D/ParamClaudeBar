import XCTest
@testable import ParamClaudeBar

final class PollingOptionFormatterTests: XCTestCase {
    func testLocalizedPollingIntervalUsesExpectedCompactLabels() {
        let locale = Locale(identifier: "en_US_POSIX")

        XCTAssertEqual(localizedPollingInterval(for: 1, locale: locale), "1m")
        XCTAssertEqual(localizedPollingInterval(for: 2, locale: locale), "2m")
        XCTAssertEqual(localizedPollingInterval(for: 5, locale: locale), "5m")
        XCTAssertEqual(localizedPollingInterval(for: 15, locale: locale), "15m")
        XCTAssertEqual(localizedPollingInterval(for: 60, locale: locale), "1h")
    }

    func testPollingOptionLabelHasNoWarningSuffix() {
        let locale = Locale(identifier: "en_US_POSIX")

        for minutes in UsageService.pollingOptions {
            XCTAssertEqual(
                pollingOptionLabel(for: minutes, locale: locale),
                localizedPollingInterval(for: minutes, locale: locale)
            )
        }
    }

    func testIsDiscouragedPollingOptionReturnsFalseForAllOptions() {
        for minutes in UsageService.pollingOptions {
            XCTAssertFalse(isDiscouragedPollingOption(minutes))
        }
    }

    func testSupportedPollingOptionsAllProduceNonEmptyLabels() {
        let locale = Locale(identifier: "en_US_POSIX")

        for minutes in UsageService.pollingOptions {
            XCTAssertFalse(pollingOptionLabel(for: minutes, locale: locale).isEmpty)
        }
    }
}

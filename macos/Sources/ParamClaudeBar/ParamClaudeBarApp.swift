import SwiftUI

@main
struct ParamClaudeBarApp: App {
    @StateObject private var service = UsageService()
    @StateObject private var historyService = UsageHistoryService()
    @StateObject private var notificationService = NotificationService()
    @StateObject private var appUpdater = AppUpdater()
    @StateObject private var settings = SettingsStore()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(
                service: service,
                historyService: historyService,
                notificationService: notificationService,
                appUpdater: appUpdater
            )
            .preferredColorScheme(settings.appearanceTheme.preferredColorScheme)
        } label: {
            MenuBarLabel(
                service: service,
                settings: settings,
                historyService: historyService
            )
            .task {
                if service.isAuthenticated && !UserDefaults.standard.bool(forKey: "setupComplete") {
                    UserDefaults.standard.set(true, forKey: "setupComplete")
                }
                historyService.loadHistory()
                service.historyService = historyService
                service.notificationService = notificationService
                service.startPolling()

                if !UserDefaults.standard.bool(forKey: "setupComplete") {
                    OnboardingWindowController.show(
                        service: service,
                        notificationService: notificationService,
                        settings: settings
                    )
                }
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsWindowContent(
                service: service,
                notificationService: notificationService,
                appUpdater: appUpdater,
                settings: settings
            )
            .preferredColorScheme(settings.appearanceTheme.preferredColorScheme)
        }
        .windowResizability(.contentSize)
        .windowStyle(.titleBar)
    }
}

private struct MenuBarLabel: View {
    @ObservedObject var service: UsageService
    @ObservedObject var settings: SettingsStore
    @ObservedObject var historyService: UsageHistoryService

    private var icon: NSImage {
        service.isAuthenticated
            ? renderIcon(pct5h: service.pct5h, pct7d: service.pct7d, monochrome: settings.useMonochromeIcon)
            : renderUnauthenticatedIcon(monochrome: settings.useMonochromeIcon)
    }

    private var percentageText: String {
        guard service.isAuthenticated else { return "—" }
        return "\(Int(round(service.pct5h * 100)))%"
    }

    /// "→2h12m" if the burn-rate hint setting is on and the 5h projection
    /// lands before the window resets. nil otherwise. SPEC §7.4.
    private var burnRateSuffix: String? {
        guard settings.showBurnRateHint, service.isAuthenticated else { return nil }
        let projection = BurnRateCalculator.project(
            points: historyService.history.dataPoints,
            valueExtractor: { $0.pct5h * 100 },
            currentPercent: service.pct5h * 100,
            resetTime: service.usage?.fiveHour?.resetsAtDate
        )
        guard let hit = projection.projectedHitTime else { return nil }
        let seconds = hit.timeIntervalSinceNow
        guard seconds > 0 else { return nil }
        let totalMin = Int(seconds / 60)
        let h = totalMin / 60
        let m = totalMin % 60
        return h > 0 ? "→\(h)h\(m)m" : "→\(m)m"
    }

    @ViewBuilder
    private var percentageView: some View {
        HStack(spacing: 2) {
            Text(percentageText)
                .monospacedDigit()
            if let suffix = burnRateSuffix {
                Text(suffix)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    var body: some View {
        switch settings.menuBarDisplayMode {
        case .iconOnly:
            Image(nsImage: icon)
        case .iconAndPercentage:
            HStack(spacing: 4) {
                Image(nsImage: icon)
                percentageView
            }
        case .percentageOnly:
            percentageView
        }
    }
}

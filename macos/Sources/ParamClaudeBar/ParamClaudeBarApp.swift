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
        } label: {
            MenuBarLabel(service: service, settings: settings)
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
                            notificationService: notificationService
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
        }
        .windowResizability(.contentSize)
        .windowStyle(.titleBar)
    }
}

private struct MenuBarLabel: View {
    @ObservedObject var service: UsageService
    @ObservedObject var settings: SettingsStore

    private var icon: NSImage {
        service.isAuthenticated
            ? renderIcon(pct5h: service.pct5h, pct7d: service.pct7d)
            : renderUnauthenticatedIcon()
    }

    private var percentageText: String {
        guard service.isAuthenticated else { return "—" }
        return "\(Int(round(service.pct5h * 100)))%"
    }

    var body: some View {
        switch settings.menuBarDisplayMode {
        case .iconOnly:
            Image(nsImage: icon)
        case .iconAndPercentage:
            HStack(spacing: 4) {
                Image(nsImage: icon)
                Text(percentageText).monospacedDigit()
            }
        case .percentageOnly:
            Text(percentageText).monospacedDigit()
        }
    }
}

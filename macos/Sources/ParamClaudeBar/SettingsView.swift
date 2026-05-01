import SwiftUI
import ServiceManagement

struct SettingsWindowContent: View {
    @ObservedObject var service: UsageService
    @ObservedObject var notificationService: NotificationService
    @ObservedObject var appUpdater: AppUpdater
    @ObservedObject var settings: SettingsStore

    var body: some View {
        TabView {
            GeneralSettingsTab(service: service, settings: settings)
                .tabItem { Label("General", systemImage: "gearshape") }

            AppearanceSettingsTab(settings: settings)
                .tabItem { Label("Appearance", systemImage: "paintpalette") }

            NotificationsSettingsTab(
                notificationService: notificationService,
                settings: settings
            )
            .tabItem { Label("Notifications", systemImage: "bell") }

            AccountSettingsTab(service: service)
                .tabItem { Label("Account", systemImage: "person.crop.circle") }

            AboutSettingsTab(appUpdater: appUpdater)
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 400)
        .onAppear { focusSettingsWindow() }
    }
}

@MainActor
private func focusSettingsWindow() {
    DispatchQueue.main.async {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.last(where: { $0.isVisible && $0.canBecomeKey }) {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }
}

// MARK: - General

private struct GeneralSettingsTab: View {
    @ObservedObject var service: UsageService
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                LaunchAtLoginToggle()

                Picker("Polling Interval", selection: Binding(
                    get: { service.pollingMinutes },
                    set: { service.updatePollingInterval($0) }
                )) {
                    ForEach(UsageService.pollingOptions, id: \.self) { mins in
                        Text(pollingOptionLabel(for: mins))
                            .tag(mins)
                    }
                }
            }

            Section("Menu bar") {
                Picker("Display", selection: $settings.menuBarDisplayMode) {
                    ForEach(MenuBarDisplayMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("Show burn-rate hint", isOn: $settings.showBurnRateHint)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Appearance

private struct AppearanceSettingsTab: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                Picker("Theme", selection: $settings.appearanceTheme) {
                    ForEach(AppearanceTheme.allCases) { theme in
                        Text(theme.label).tag(theme)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("Use monochrome icon", isOn: $settings.useMonochromeIcon)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Notifications

private struct NotificationsSettingsTab: View {
    @ObservedObject var notificationService: NotificationService
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            Section("Thresholds") {
                ThresholdSlider(
                    label: "5-hour window",
                    value: notificationService.threshold5h,
                    onChange: { notificationService.setThreshold5h($0) }
                )
                ThresholdSlider(
                    label: "7-day window",
                    value: notificationService.threshold7d,
                    onChange: { notificationService.setThreshold7d($0) }
                )
                ThresholdSlider(
                    label: "Extra usage",
                    value: notificationService.thresholdExtra,
                    onChange: { notificationService.setThresholdExtra($0) }
                )
            }

            Section("Alerts") {
                Toggle("Warning notification", isOn: $settings.notifyWarningEnabled)
                Toggle("Critical notification", isOn: $settings.notifyCriticalEnabled)
                Toggle("Burn-rate alert", isOn: $settings.notifyBurnRateEnabled)
                Toggle("Reset notification", isOn: $settings.notifyResetEnabled)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Account

private struct AccountSettingsTab: View {
    @ObservedObject var service: UsageService

    var body: some View {
        Form {
            Section {
                if service.isAuthenticated {
                    LabeledContent("Status") {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(.green)
                                .frame(width: 8, height: 8)
                            Text("Signed in")
                        }
                    }
                    if let email = service.accountEmail {
                        LabeledContent("Account", value: email)
                    }
                    if let updated = service.lastUpdated {
                        LabeledContent("Last poll") {
                            Text(updated, style: .relative) + Text(" ago")
                        }
                    }
                    Button("Sign Out") {
                        service.signOut()
                    }
                } else {
                    LabeledContent("Status") {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(.secondary)
                                .frame(width: 8, height: 8)
                            Text("Not signed in")
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - About

private struct AboutSettingsTab: View {
    @ObservedObject var appUpdater: AppUpdater

    private var versionLine: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 16) {
            if let appIcon = NSImage(named: NSImage.applicationIconName) {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 96, height: 96)
            }
            Text("ParamClaudeBar")
                .font(.title2.weight(.semibold))
            Text(versionLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if appUpdater.isConfigured {
                Button("Check for Updates…") {
                    appUpdater.checkForUpdates()
                }
                .disabled(!appUpdater.canCheckForUpdates)
            }

            Spacer()

            Text("Forked from [Blimp-Labs/claude-usage-bar](https://github.com/Blimp-Labs/claude-usage-bar) under BSD-2-Clause.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Launch at login (preserved from upstream)

struct LaunchAtLoginToggle: View {
    @StateObject private var model: LaunchAtLoginModel
    private let controlSize: ControlSize
    private let useSwitchStyle: Bool

    init(
        controlSize: ControlSize = .regular,
        useSwitchStyle: Bool = false,
        bundleURL: URL = Bundle.main.bundleURL
    ) {
        _model = StateObject(
            wrappedValue: LaunchAtLoginModel(bundleURL: bundleURL)
        )
        self.controlSize = controlSize
        self.useSwitchStyle = useSwitchStyle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            toggle

            if let message = model.message {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var toggle: some View {
        let baseToggle = Toggle("Launch at Login", isOn: Binding(
            get: { model.isEnabled },
            set: { model.setEnabled($0) }
        ))
        .disabled(!model.isSupported)
        .controlSize(controlSize)

        if useSwitchStyle {
            baseToggle.toggleStyle(.switch)
        } else {
            baseToggle
        }
    }
}

@MainActor
final class LaunchAtLoginModel: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var isSupported: Bool
    @Published private(set) var message: String?

    init(bundleURL: URL = Bundle.main.bundleURL) {
        isSupported = supportsLaunchAtLoginManagement(appURL: bundleURL)

        guard isSupported else {
            message = "Install the app in Applications to manage launch at login."
            return
        }

        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        guard isSupported else { return }

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            isEnabled = enabled
            message = nil
        } catch {
            isEnabled = SMAppService.mainApp.status == .enabled
            message = "Could not update launch at login."
        }
    }
}

func supportsLaunchAtLoginManagement(
    appURL: URL = Bundle.main.bundleURL,
    installDirectories: [URL] = launchAtLoginInstallDirectories()
) -> Bool {
    let normalizedAppURL = appURL.resolvingSymlinksInPath().standardizedFileURL

    return installDirectories.contains { directory in
        let normalizedDirectory = directory.resolvingSymlinksInPath().standardizedFileURL
        let directoryPath = normalizedDirectory.path
        let appPath = normalizedAppURL.path

        return appPath == directoryPath || appPath.hasPrefix(directoryPath + "/")
    }
}

func launchAtLoginInstallDirectories(fileManager: FileManager = .default) -> [URL] {
    [
        URL(fileURLWithPath: "/Applications", isDirectory: true),
        fileManager.homeDirectoryForCurrentUser.appending(path: "Applications", directoryHint: .isDirectory)
    ]
}

// MARK: - Threshold slider

private struct ThresholdSlider: View {
    let label: String
    let value: Int
    let onChange: (Int) -> Void

    var body: some View {
        LabeledContent {
            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { onChange(Int($0)) }
                ),
                in: 0...100,
                step: 5
            )
        } label: {
            Text(label)
            Text(value > 0 ? "\(value)%" : "Off")
                .foregroundStyle(.secondary)
        }
        .alignmentGuide(.firstTextBaseline) { d in
            d[VerticalAlignment.center]
        }
    }
}

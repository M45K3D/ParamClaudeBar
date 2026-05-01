import SwiftUI

struct PopoverView: View {
    @ObservedObject var service: UsageService
    @ObservedObject var historyService: UsageHistoryService
    @ObservedObject var notificationService: NotificationService
    @ObservedObject var appUpdater: AppUpdater
    @AppStorage("setupComplete") private var setupComplete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !setupComplete && !service.isAuthenticated {
                SetupView(
                    service: service,
                    notificationService: notificationService,
                    onComplete: { setupComplete = true }
                )
            } else {
                PopoverHeader(service: service)

                if !service.isAuthenticated {
                    signInBody
                } else {
                    authenticatedBody
                }
            }
        }
        .padding(16)
        .frame(width: 380)
        .background(.regularMaterial)
        .animation(.easeInOut(duration: 0.2), value: service.isAuthenticated)
    }

    // MARK: - Sign-in (post-onboarding sign-out fallback)

    @ViewBuilder
    private var signInBody: some View {
        if service.isAwaitingCode {
            CodeEntryView(service: service)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("Sign in to view your usage.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Sign in with Claude") { service.startOAuthFlow() }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
            }
        }

        if let error = service.lastError {
            Label(error, systemImage: "exclamationmark.triangle")
                .foregroundStyle(Theme.error)
                .font(.caption)
        }

        PopoverFooter(service: service)
    }

    // MARK: - Authenticated body

    @ViewBuilder
    private var authenticatedBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            UsageBucketRow(
                label: "5-hour window",
                bucket: service.usage?.fiveHour,
                tintForFraction: Theme.fiveHourTint(forFraction:)
            )

            UsageBucketRow(
                label: "7-day window",
                bucket: service.usage?.sevenDay,
                tintForFraction: Theme.sevenDayTint(forFraction:)
            )

            if let opus = service.usage?.sevenDayOpus,
               opus.utilization != nil {
                Divider()
                Text("Per-Model (7 day)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                UsageBucketRow(
                    label: "Opus",
                    bucket: opus,
                    tintForFraction: Theme.sevenDayTint(forFraction:)
                )
                if let sonnet = service.usage?.sevenDaySonnet {
                    UsageBucketRow(
                        label: "Sonnet",
                        bucket: sonnet,
                        tintForFraction: Theme.sevenDayTint(forFraction:)
                    )
                }
            }

            if let extra = service.usage?.extraUsage, extra.isEnabled {
                Divider()
                ExtraUsageRow(extra: extra)
            }
        }

        Divider()
        UsageChartView(historyService: historyService)

        if let error = service.lastError {
            Label(error, systemImage: "exclamationmark.triangle")
                .foregroundStyle(Theme.error)
                .font(.caption)
        }

        if let updaterError = appUpdater.lastError {
            Label(updaterError, systemImage: "arrow.triangle.2.circlepath.circle")
                .foregroundStyle(Theme.error)
                .font(.caption)
        }

        PopoverFooter(service: service)
    }
}

// MARK: - Header (§8.1)

private struct PopoverHeader: View {
    @ObservedObject var service: UsageService
    @State private var ticker = Date()

    private let tickerTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("ParamClaudeBar")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            if let updated = service.lastUpdated {
                Text("Updated \(relativeUpdatedString(from: updated, now: ticker))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Button {
                Task { await service.fetchUsage() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh now")
            .keyboardShortcut("r", modifiers: .command)
        }
        .onReceive(tickerTimer) { ticker = $0 }
    }
}

private func relativeUpdatedString(from updated: Date, now: Date) -> String {
    let interval = max(0, now.timeIntervalSince(updated))
    if interval < 60 {
        return "\(Int(interval))s ago"
    }
    if interval < 3600 {
        return "\(Int(interval / 60))m ago"
    }
    return "\(Int(interval / 3600))h ago"
}

// MARK: - Footer (§8.5)

private struct PopoverFooter: View {
    @ObservedObject var service: UsageService

    var body: some View {
        HStack {
            SettingsLink {
                Text("Settings…")
            }
            .buttonStyle(.borderless)
            .font(.caption)

            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .fill(service.isAuthenticated ? Color(nsColor: .systemGreen) : Color.secondary)
                    .frame(width: 7, height: 7)
                Text(service.isAuthenticated ? "Signed in" : "Not signed in")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(.secondary)
                .keyboardShortcut("q", modifiers: .command)
        }
    }
}

// MARK: - Setup (first launch — Phase 9 will redesign)

private struct SetupView: View {
    @ObservedObject var service: UsageService
    @ObservedObject var notificationService: NotificationService
    var onComplete: () -> Void

    var body: some View {
        Text("Welcome")
            .font(.headline)
        Text("Configure your preferences to get started.")
            .font(.subheadline)
            .foregroundStyle(.secondary)

        Divider()

        LaunchAtLoginToggle(controlSize: .small, useSwitchStyle: true)

        Divider()

        VStack(alignment: .leading, spacing: 8) {
            Text("Notifications")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            SetupThresholdSlider(
                label: "5-hour window",
                value: notificationService.threshold5h,
                onChange: { notificationService.setThreshold5h($0) }
            )
            SetupThresholdSlider(
                label: "7-day window",
                value: notificationService.threshold7d,
                onChange: { notificationService.setThreshold7d($0) }
            )
            SetupThresholdSlider(
                label: "Extra usage",
                value: notificationService.thresholdExtra,
                onChange: { notificationService.setThresholdExtra($0) }
            )
        }

        Divider()

        VStack(alignment: .leading, spacing: 6) {
            Text("Polling Interval")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker("", selection: Binding(
                get: { service.pollingMinutes },
                set: { service.updatePollingInterval($0) }
            )) {
                ForEach(UsageService.pollingOptions, id: \.self) { mins in
                    Text(localizedPollingInterval(for: mins, locale: .autoupdatingCurrent))
                        .tag(mins)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if isDiscouragedPollingOption(service.pollingMinutes) {
                Text("Frequent polling may cause rate limiting")
                    .font(.caption2)
                    .foregroundStyle(Theme.warning)
            }
        }

        Divider()

        Button("Get Started") { onComplete() }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)

        HStack {
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Code entry (paste-back UI)

private struct CodeEntryView: View {
    @ObservedObject var service: UsageService
    @State private var code = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Paste the code from your browser:")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                TextField("code#state", text: $code)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit { submit() }
                Button {
                    if let str = NSPasteboard.general.string(forType: .string) {
                        code = str.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                } label: {
                    Image(systemName: "doc.on.clipboard")
                }
                .buttonStyle(.borderless)
            }

            HStack {
                Button("Cancel") { service.isAwaitingCode = false }
                    .buttonStyle(.borderless)
                Spacer()
                Button("Submit") { submit() }
                    .buttonStyle(.borderedProminent)
                    .disabled(code.isEmpty)
            }
        }
    }

    private func submit() {
        let value = code
        Task { await service.submitOAuthCode(value) }
    }
}

// MARK: - Usage row (§8.2)

private struct UsageBucketRow: View {
    let label: String
    let bucket: UsageBucket?
    let tintForFraction: (Double) -> Color

    private var fraction: Double {
        max(0, min(1, (bucket?.utilization ?? 0) / 100.0))
    }

    private var percentageText: String {
        guard let pct = bucket?.utilization else { return "—" }
        return "\(Int(round(pct)))%"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.body)
                Spacer()
                Text(percentageText)
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.2), value: fraction)
            }

            ProgressView(value: fraction, total: 1)
                .progressViewStyle(.linear)
                .tint(tintForFraction(fraction))
                .frame(height: 8)

            if let resetDate = bucket?.resetsAtDate {
                Text(resetWallClock(for: resetDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(resetDate, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private func resetWallClock(for date: Date, calendar: Calendar = .current, now: Date = Date()) -> String {
    let locale = Locale(identifier: "en_GB")
    var cal = calendar
    cal.locale = locale

    let resetDay = cal.startOfDay(for: date)
    let today = cal.startOfDay(for: now)
    let dayOffset = cal.dateComponents([.day], from: today, to: resetDay).day ?? 0

    let timeFormat = Date.FormatStyle.dateTime.hour().minute().locale(locale)
    let timeString = date.formatted(timeFormat)

    switch dayOffset {
    case 0: return "Resets at \(timeString)"
    case 1: return "Resets tomorrow at \(timeString)"
    default:
        let weekday = date.formatted(.dateTime.weekday(.abbreviated).locale(locale))
        return "Resets \(weekday) \(timeString)"
    }
}

// MARK: - Extra usage row

private struct ExtraUsageRow: View {
    let extra: ExtraUsage

    private var fraction: Double {
        max(0, min(1, (extra.utilization ?? 0) / 100.0))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Extra usage")
                    .font(.body)
                Spacer()
                if let pct = extra.utilization {
                    Text("\(Int(round(pct)))%")
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.2), value: fraction)
                }
            }

            if let used = extra.usedCreditsAmount, let limit = extra.monthlyLimitAmount {
                Text("\(ExtraUsage.formatUSD(used)) / \(ExtraUsage.formatUSD(limit))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            ProgressView(value: fraction, total: 1)
                .progressViewStyle(.linear)
                .tint(Theme.extraUsageAccent)
                .frame(height: 8)
        }
    }
}

// MARK: - Setup helper (preserved)

private struct SetupThresholdSlider: View {
    let label: String
    let value: Int
    let onChange: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(.callout)
                Spacer()
                Text(value > 0 ? "\(value)%" : "Off")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { onChange(Int($0)) }
                ),
                in: 0...100,
                step: 5
            )
            .controlSize(.small)
        }
    }
}

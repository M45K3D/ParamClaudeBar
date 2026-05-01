import SwiftUI
import Charts

struct PopoverView: View {
    @ObservedObject var service: UsageService
    @ObservedObject var historyService: UsageHistoryService
    @ObservedObject var notificationService: NotificationService
    @ObservedObject var appUpdater: AppUpdater
    @AppStorage("setupComplete") private var setupComplete = false

    var body: some View {
        Group {
            if !setupComplete && !service.isAuthenticated {
                VStack(alignment: .leading, spacing: 18) {
                    SetupView(
                        service: service,
                        notificationService: notificationService,
                        onComplete: { setupComplete = true }
                    )
                }
                .padding(16)
            } else if service.isAuthenticated {
                authenticatedCard
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    PopoverHeader(service: service)
                    signInBody
                }
                .padding(16)
            }
        }
        .frame(width: 320)
        .background(.regularMaterial)
        .animation(.easeInOut(duration: 0.2), value: service.isAuthenticated)
    }

    @ViewBuilder
    private var authenticatedCard: some View {
        VStack(spacing: 0) {
            authenticatedBody
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .padding(10)
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
        VStack(spacing: 18) {
            Text("Claude Usage")
                .font(.headline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)

            VStack(spacing: 16) {
                WindowRow(
                    label: "Session (5 hour)",
                    bucket: service.usage?.fiveHour,
                    tintForFraction: Theme.fiveHourTint(forFraction:)
                )
                WindowRow(
                    label: "Weekly (7 day)",
                    bucket: service.usage?.sevenDay,
                    tintForFraction: Theme.sevenDayTint(forFraction:)
                )

                if let opus = service.usage?.sevenDayOpus, opus.utilization != nil {
                    InlineModelLine(opus: opus, sonnet: service.usage?.sevenDaySonnet)
                        .padding(.top, 2)
                }
                if let extra = service.usage?.extraUsage, extra.isEnabled {
                    InlineExtraUsageLine(extra: extra)
                }
                if service.usage?.fiveHour != nil {
                    BurnRateSentence(
                        projection: BurnRateCalculator.project(
                            points: historyService.history.dataPoints,
                            valueExtractor: { $0.pct5h * 100 },
                            currentPercent: service.pct5h * 100,
                            resetTime: service.usage?.fiveHour?.resetsAtDate
                        )
                    )
                }
            }

            DisclosureView(label: "History") {
                UsageChartView(historyService: historyService)
                    .padding(.top, 4)
            }

            if let error = service.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Theme.error)
                    .font(.caption2)
            }
            if let updaterError = appUpdater.lastError {
                Label(updaterError, systemImage: "arrow.triangle.2.circlepath.circle")
                    .foregroundStyle(Theme.error)
                    .font(.caption2)
            }

            Divider()
                .opacity(0.4)

            CardFooter(service: service)
        }
    }
}

// MARK: - Header (§8.1)

private struct PopoverHeader: View {
    @ObservedObject var service: UsageService
    @State private var ticker = Date()

    private let tickerTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("PARAMCLAUDEBAR")
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(.secondary)

            Spacer()

            if let updated = service.lastUpdated {
                Text(relativeUpdatedString(from: updated, now: ticker))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }

            Button {
                Task { await service.fetchUsage() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .medium))
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
        HStack(spacing: 14) {
            SettingsLink {
                Text("Settings")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)

            Spacer()

            Circle()
                .fill(service.isAuthenticated ? Color(nsColor: .systemGreen) : Color.secondary)
                .frame(width: 5, height: 5)

            Spacer()

            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
                .font(.system(size: 10))
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

// MARK: - Window row (single card layout, fat capsule bar)

private struct WindowRow: View {
    let label: String
    let bucket: UsageBucket?
    let tintForFraction: (Double) -> Color

    private var fraction: Double {
        max(0, min(1, (bucket?.utilization ?? 0) / 100.0))
    }
    private var pctInt: Int {
        Int(round((bucket?.utilization ?? 0)))
    }
    private var hasData: Bool { bucket?.utilization != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
                if let resetDate = bucket?.resetsAtDate {
                    Text(resetWallClock(for: resetDate, prefix: true))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            FatCapsuleBar(fraction: fraction, tint: tintForFraction(fraction))

            HStack(spacing: 6) {
                if fraction >= 0.85 {
                    PulsingDot(color: tintForFraction(fraction))
                }
                Text(hasData ? "\(pctInt)% used" : "—")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .animation(.easeInOut(duration: 0.25), value: fraction)
    }
}

private struct FatCapsuleBar: View {
    let fraction: Double
    let tint: Color
    private let height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.10))
                Capsule()
                    .fill(tint)
                    .frame(width: max(height, geo.size.width * fraction))
            }
        }
        .frame(height: height)
    }
}

private struct CardFooter: View {
    @ObservedObject var service: UsageService
    @State private var ticker = Date()
    private let tickerTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                if let updated = service.lastUpdated {
                    Text("Last updated: \(updated.formatted(.dateTime.hour().minute().locale(.init(identifier: "en_GB"))))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                } else {
                    Text(" ")
                        .font(.system(size: 11))
                }
                Spacer()
                Button {
                    Task { await service.fetchUsage() }
                } label: {
                    Text("Refresh")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .keyboardShortcut("r", modifiers: .command)
            }

            HStack {
                SettingsLink {
                    Text("Settings")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)

                Spacer()

                Circle()
                    .fill(service.isAuthenticated ? Color(nsColor: .systemGreen) : Color.secondary)
                    .frame(width: 5, height: 5)

                Spacer()

                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .keyboardShortcut("q", modifiers: .command)
            }
        }
        .onReceive(tickerTimer) { ticker = $0 }
    }
}

// MARK: - Disclosure (tap to reveal the chart)

private struct DisclosureView<Content: View>: View {
    let label: String
    @ViewBuilder var content: () -> Content
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                    Text(label.uppercased())
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(1.4)
                    Spacer()
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if expanded {
                content()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

private struct PulsingDot: View {
    let color: Color
    @State private var scale: CGFloat = 1.0

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .scaleEffect(scale)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    scale = 1.5
                }
            }
    }
}

// MARK: - Inline per-model line

private struct InlineModelLine: View {
    let opus: UsageBucket
    let sonnet: UsageBucket?

    var body: some View {
        HStack(spacing: 14) {
            modelChip(label: "Opus", bucket: opus)
            if let sonnet {
                modelChip(label: "Sonnet", bucket: sonnet)
            }
            Spacer()
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }

    @ViewBuilder
    private func modelChip(label: String, bucket: UsageBucket) -> some View {
        if let pct = bucket.utilization {
            HStack(spacing: 4) {
                Circle()
                    .fill(Theme.sevenDayTint(forFraction: pct / 100))
                    .frame(width: 5, height: 5)
                Text(label)
                Text("\(Int(round(pct)))%")
                    .foregroundStyle(.primary)
            }
        }
    }
}

private struct InlineExtraUsageLine: View {
    let extra: ExtraUsage

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Theme.extraUsageAccent)
                .frame(width: 5, height: 5)
            Text("Extra")
            if let used = extra.usedCreditsAmount, let limit = extra.monthlyLimitAmount {
                Text("\(ExtraUsage.formatUSD(used)) / \(ExtraUsage.formatUSD(limit))")
                    .foregroundStyle(.primary)
            }
            if let pct = extra.utilization {
                Text("·")
                    .foregroundStyle(.tertiary)
                Text("\(Int(round(pct)))%")
            }
            Spacer()
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }
}

// MARK: - Burn-rate sentence (replaces the three-card insights grid)

private struct BurnRateSentence: View {
    let projection: BurnRateProjection

    var body: some View {
        HStack(spacing: 4) {
            Text(verbatim: leading)
                .foregroundStyle(.secondary)
            if let trailing {
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(verbatim: trailing)
                    .foregroundStyle(.primary)
            }
            Spacer()
        }
        .font(.system(size: 10))
        .monospacedDigit()
    }

    private var leading: String {
        if projection.burnRatePerHour > 0 {
            return "Burning at \(formatRate(projection.burnRatePerHour))%/h"
        } else if projection.burnRatePerHour < 0 {
            return "Recovering"
        } else {
            return "Idle"
        }
    }

    private var trailing: String? {
        if let hit = projection.projectedHitTime {
            let time = hit.formatted(.dateTime.hour().minute().locale(.init(identifier: "en_GB")))
            return "hit \(time)"
        } else if projection.burnRatePerHour > 0 {
            return "on track"
        }
        return nil
    }
}

private func resetWallClock(
    for date: Date,
    calendar: Calendar = .current,
    now: Date = Date(),
    prefix: Bool = true
) -> String {
    let locale = Locale(identifier: "en_GB")
    var cal = calendar
    cal.locale = locale

    let resetDay = cal.startOfDay(for: date)
    let today = cal.startOfDay(for: now)
    let dayOffset = cal.dateComponents([.day], from: today, to: resetDay).day ?? 0

    let timeFormat = Date.FormatStyle.dateTime.hour().minute().locale(locale)
    let timeString = date.formatted(timeFormat)

    let body: String
    switch dayOffset {
    case 0:
        body = prefix ? "at \(timeString)" : "at \(timeString)"
    case 1:
        body = prefix ? "tomorrow at \(timeString)" : "tomorrow at \(timeString)"
    default:
        let weekday = date.formatted(.dateTime.weekday(.abbreviated).locale(locale))
        body = "\(weekday) \(timeString)"
    }
    return prefix ? "Resets \(body)" : body
}

private func formatRate(_ value: Double) -> String {
    String(format: "%.1f", value)
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

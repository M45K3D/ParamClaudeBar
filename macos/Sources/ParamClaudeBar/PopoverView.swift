import SwiftUI
import Charts

struct PopoverView: View {
    @ObservedObject var service: UsageService
    @ObservedObject var historyService: UsageHistoryService
    @ObservedObject var notificationService: NotificationService
    @ObservedObject var appUpdater: AppUpdater
    @AppStorage("setupComplete") private var setupComplete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
        .padding(12)
        .frame(width: 300)
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
        VStack(alignment: .leading, spacing: 10) {
            WindowGauge(
                label: "5h",
                bucket: service.usage?.fiveHour,
                tintForFraction: Theme.fiveHourTint(forFraction:)
            )
            WindowGauge(
                label: "7d",
                bucket: service.usage?.sevenDay,
                tintForFraction: Theme.sevenDayTint(forFraction:)
            )
        }

        if let opus = service.usage?.sevenDayOpus,
           opus.utilization != nil {
            ModelChipsRow(
                opus: opus,
                sonnet: service.usage?.sevenDaySonnet
            )
        }

        if let extra = service.usage?.extraUsage, extra.isEnabled {
            ExtraUsageRow(extra: extra)
        }

        if service.usage?.fiveHour != nil {
            Divider()
            InsightsRow(
                projection: BurnRateCalculator.project(
                    points: historyService.history.dataPoints,
                    valueExtractor: { $0.pct5h * 100 },
                    currentPercent: service.pct5h * 100,
                    resetTime: service.usage?.fiveHour?.resetsAtDate
                ),
                sparklinePoints: sparklineWindow(historyService.history.dataPoints)
            )
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

// MARK: - Window gauge (the "magic" — big numerals + thin tinted bar)

private struct WindowGauge: View {
    let label: String
    let bucket: UsageBucket?
    let tintForFraction: (Double) -> Color

    private var fraction: Double {
        max(0, min(1, (bucket?.utilization ?? 0) / 100.0))
    }
    private var pctInt: Int {
        Int(round((bucket?.utilization ?? 0)))
    }
    private var hasData: Bool {
        bucket?.utilization != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(label.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(1.0)
                Text("\(pctInt)%")
                    .font(.system(.callout, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(hasData ? .primary : .tertiary)
                if fraction >= 0.85 {
                    PulsingDot(color: tintForFraction(fraction))
                }
                Spacer()
                if let resetDate = bucket?.resetsAtDate {
                    Text(resetWallClock(for: resetDate, prefix: false))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Text("·")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(resetDate, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            GaugeBar(fraction: fraction, tint: tintForFraction(fraction))
        }
        .animation(.easeInOut(duration: 0.25), value: fraction)
    }
}

private struct GaugeBar: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.15))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.85), tint],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, geo.size.width * fraction))
            }
        }
        .frame(height: 4)
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

// MARK: - Per-model chips

private struct ModelChipsRow: View {
    let opus: UsageBucket
    let sonnet: UsageBucket?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Per-model · 7 day")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.6)

            HStack(spacing: 8) {
                ModelChip(label: "Opus", bucket: opus)
                if let sonnet {
                    ModelChip(label: "Sonnet", bucket: sonnet)
                }
            }
        }
    }
}

private struct ModelChip: View {
    let label: String
    let bucket: UsageBucket

    private var fraction: Double {
        max(0, min(1, (bucket.utilization ?? 0) / 100.0))
    }
    private var percentText: String {
        guard let pct = bucket.utilization else { return "—" }
        return "\(Int(round(pct)))%"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption.weight(.medium))
                Spacer()
                Text(percentText)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
            }
            ProgressView(value: fraction, total: 1)
                .progressViewStyle(.linear)
                .tint(Theme.sevenDayTint(forFraction: fraction))
                .frame(height: 4)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
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

// MARK: - Insights row (§8.3)

private let sparklineWindowMinutes: Double = 60

private func sparklineWindow(_ points: [UsageDataPoint], now: Date = Date()) -> [UsageDataPoint] {
    let cutoff = now.addingTimeInterval(-sparklineWindowMinutes * 60)
    return points.filter { $0.timestamp >= cutoff && $0.timestamp <= now }
}

private struct InsightsRow: View {
    let projection: BurnRateProjection
    let sparklinePoints: [UsageDataPoint]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            InsightCard(title: "Burn rate") {
                burnRateView
            }
            InsightCard(title: "Projection") {
                projectionView
            }
            InsightCard(title: "Pace") {
                if sparklinePoints.count >= 2 {
                    PaceSparkline(points: sparklinePoints)
                } else {
                    Text("—")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder
    private var burnRateView: some View {
        if projection.burnRatePerHour > 0 {
            Text("\(formatRate(projection.burnRatePerHour))%/h")
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .monospacedDigit()
        } else if projection.burnRatePerHour < 0 {
            Text("Recovering")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        } else {
            Text("Idle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var projectionView: some View {
        if let hit = projection.projectedHitTime {
            Text("\(hit.formatted(.dateTime.hour().minute().locale(.init(identifier: "en_GB"))))")
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .monospacedDigit()
        } else if projection.burnRatePerHour > 0 {
            Text("On track")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        } else if projection.burnRatePerHour < 0 {
            Text("Recovering")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        } else {
            Text("Idle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

private func formatRate(_ value: Double) -> String {
    String(format: "%.1f", value)
}

private struct InsightCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .tracking(0.6)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct PaceSparkline: View {
    let points: [UsageDataPoint]

    var body: some View {
        Chart {
            ForEach(points) { p in
                LineMark(
                    x: .value("t", p.timestamp),
                    y: .value("pct", p.pct5h * 100)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(Theme.fiveHourAccent)
            }
            ForEach(points) { p in
                AreaMark(
                    x: .value("t", p.timestamp),
                    y: .value("pct", p.pct5h * 100)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        colors: [Theme.fiveHourAccent.opacity(0.25), Theme.fiveHourAccent.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...100)
        .chartLegend(.hidden)
        .frame(height: 24)
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

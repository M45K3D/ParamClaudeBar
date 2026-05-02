import SwiftUI
import Charts

struct PopoverView: View {
    @ObservedObject var service: UsageService
    @ObservedObject var historyService: UsageHistoryService
    @ObservedObject var notificationService: NotificationService
    @ObservedObject var appUpdater: AppUpdater

    var body: some View {
        Group {
            if service.isAuthenticated {
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
                    label: "5-hour limit",
                    bucket: service.usage?.fiveHour,
                    tintForFraction: Theme.fiveHourTint(forFraction:)
                )
                WindowRow(
                    label: "7-day limit",
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

            UsageChartView(historyService: historyService)
                .padding(.top, 4)

            if let error = service.lastError {
                let isSlowdown = error.lowercased().contains("slowing down")
                Label(
                    error,
                    systemImage: isSlowdown ? "clock.arrow.circlepath" : "exclamationmark.triangle"
                )
                .foregroundStyle(isSlowdown ? Theme.warning : Theme.error)
                .font(.caption2)
            }
            if let updaterError = appUpdater.lastError {
                Label(updaterError, systemImage: "arrow.triangle.2.circlepath.circle")
                    .foregroundStyle(Theme.error)
                    .font(.caption2)
            }

            Divider()
                .opacity(0.4)

            CardFooter(service: service, appUpdater: appUpdater)
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
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
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
    @ObservedObject var appUpdater: AppUpdater
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
                if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                    Text("v\(version)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                        .padding(.trailing, 8)
                }
                Button {
                    Task { await service.fetchUsage() }
                } label: {
                    Text("Refresh")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .keyboardShortcut("r", modifiers: .command)
            }

            HStack(spacing: 4) {
                SettingsLink {
                    Text("Settings")
                }
                .buttonStyle(FooterLinkButtonStyle())

                if appUpdater.isConfigured {
                    Button {
                        appUpdater.checkForUpdates()
                    } label: {
                        Text("Check for updates")
                    }
                    .buttonStyle(FooterLinkButtonStyle())
                    .disabled(!appUpdater.canCheckForUpdates)
                }

                Spacer()

                Circle()
                    .fill(service.isAuthenticated ? Color(nsColor: .systemGreen) : Color.secondary)
                    .frame(width: 5, height: 5)

                Spacer()

                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(FooterLinkButtonStyle())
                    .keyboardShortcut("q", modifiers: .command)
            }
        }
        .onReceive(tickerTimer) { ticker = $0 }
    }
}

// MARK: - Footer link button style

private struct FooterLinkButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10))
            .foregroundStyle(foreground(pressed: configuration.isPressed))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.primary.opacity(background(pressed: configuration.isPressed)))
            )
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovering)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }

    private func foreground(pressed: Bool) -> HierarchicalShapeStyle {
        guard isEnabled else { return .quaternary }
        if pressed || isHovering { return .secondary }
        return .tertiary
    }

    private func background(pressed: Bool) -> Double {
        guard isEnabled else { return 0 }
        if pressed { return 0.10 }
        if isHovering { return 0.06 }
        return 0
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
    if dayOffset == 0 {
        body = "at \(timeString)"
    } else {
        let weekday = date.formatted(.dateTime.weekday(.abbreviated).locale(locale))
        body = "\(weekday) \(timeString)"
    }
    return prefix ? "Resets \(body)" : body
}

private func formatRate(_ value: Double) -> String {
    String(format: "%.1f", value)
}


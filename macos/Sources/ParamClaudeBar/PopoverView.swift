import SwiftUI

struct PopoverView: View {
    @ObservedObject var service: UsageService
    @ObservedObject var notificationService: NotificationService
    @ObservedObject var appUpdater: AppUpdater
    @ObservedObject var sessionMonitor: ClaudeCodeSessionMonitor

    private let sessionRefreshTimer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()

    /// Drives the live "Resets in …" countdowns and the idle label.
    @State private var ticker = Date()
    private let countdownTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

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
        .onAppear {
            sessionMonitor.refresh()
            ticker = Date()
        }
        .onReceive(sessionRefreshTimer) { _ in sessionMonitor.refresh() }
        .onReceive(countdownTimer) { ticker = $0 }
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
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 7) {
                ClaudeLogoShape()
                    .fill(Color.primary)
                    .frame(width: 15, height: 15)
                Text("Claude Usage")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 14) {
                UsageSection(
                    title: "Current session",
                    bucket: service.usage?.fiveHour,
                    tint: Theme.fiveHourTint(forFraction:),
                    now: ticker
                )
                UsageSection(
                    title: "All models",
                    bucket: service.usage?.sevenDay,
                    tint: Theme.sevenDayTint(forFraction:),
                    now: ticker
                )

                if let session = sessionMonitor.session {
                    let idle = session.isIdle(now: ticker)
                    UsageSection(
                        title: "Context",
                        subtitle: session.modelLabel,
                        fraction: session.contextFraction,
                        percentText: "\(session.contextPercent)% Used",
                        trailing: idle
                            ? "Idle \(idleLabel(session.idleSeconds(now: ticker)))"
                            : nil,
                        tint: Theme.fiveHourTint(forFraction: session.contextFraction)
                    )
                    .opacity(idle ? 0.55 : 1)
                }
            }

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

// MARK: - Usage section (title over bar over "N% Used · Resets in …")

private struct UsageSection: View {
    let title: String
    var subtitle: String? = nil
    let fraction: Double
    let percentText: String
    var trailing: String? = nil
    let tint: Color

    /// Convenience initialiser for an account window bucket.
    init(
        title: String,
        bucket: UsageBucket?,
        tint: (Double) -> Color,
        now: Date
    ) {
        let pct = bucket?.utilization
        let fraction = max(0, min(1, (pct ?? 0) / 100.0))
        self.title = title
        self.subtitle = nil
        self.fraction = fraction
        self.percentText = pct.map { "\(Int(round($0)))% Used" } ?? "—"
        self.trailing = bucket?.resetsAtDate.map { resetLabel(for: $0, now: now) }
        self.tint = tint(fraction)
    }

    /// Full control, used by the Claude Code context section.
    init(
        title: String,
        subtitle: String? = nil,
        fraction: Double,
        percentText: String,
        trailing: String? = nil,
        tint: Color
    ) {
        self.title = title
        self.subtitle = subtitle
        self.fraction = fraction
        self.percentText = percentText
        self.trailing = trailing
        self.tint = tint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                if let subtitle {
                    Spacer(minLength: 4)
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }

            SlimBar(fraction: fraction, tint: tint)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(percentText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                if let trailing {
                    Spacer(minLength: 4)
                    Text(trailing)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.25), value: fraction)
    }
}

/// Compact "20m" / "3h" / "2d" idle duration from a seconds interval.
private func idleLabel(_ seconds: TimeInterval) -> String {
    let mins = Int(seconds / 60)
    if mins < 60 { return "\(max(1, mins))m" }
    let hours = mins / 60
    if hours < 24 { return "\(hours)h" }
    return "\(hours / 24)d"
}

/// A countdown while the reset is near ("Resets in 51 min"), switching to an
/// absolute day + time once it is far enough out that a countdown stops being
/// useful ("Resets Thu 00:00"). Times stay en_GB to match the rest of the app.
func resetLabel(for date: Date, now: Date = Date()) -> String {
    let seconds = date.timeIntervalSince(now)
    guard seconds > 0 else { return "Resetting…" }

    let minutes = Int(seconds / 60)
    if minutes < 1 { return "Resets in <1 min" }
    if minutes < 60 { return "Resets in \(minutes) min" }

    let hours = minutes / 60
    if hours < 12 {
        let remainder = minutes % 60
        return remainder == 0
            ? "Resets in \(hours) hr"
            : "Resets in \(hours) hr \(remainder) min"
    }

    let locale = Locale(identifier: "en_GB")
    var calendar = Calendar.current
    calendar.locale = locale
    let time = date.formatted(.dateTime.hour().minute().locale(locale))
    let dayOffset = calendar.dateComponents(
        [.day],
        from: calendar.startOfDay(for: now),
        to: calendar.startOfDay(for: date)
    ).day ?? 0
    if dayOffset == 0 { return "Resets \(time)" }
    let weekday = date.formatted(.dateTime.weekday(.abbreviated).locale(locale))
    return "Resets \(weekday) \(time)"
}

private struct SlimBar: View {
    let fraction: Double
    let tint: Color
    private let height: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.13))
                Capsule()
                    .fill(tint)
                    .frame(width: max(fraction > 0 ? height : 0, geo.size.width * fraction))
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
                RefreshButton(isFetching: service.isFetching) {
                    Task { await service.fetchUsage() }
                }
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

// MARK: - Refresh button

private struct RefreshButton: View {
    let isFetching: Bool
    let action: () -> Void

    @State private var isHovering = false
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .semibold))
                    .rotationEffect(.degrees(isFetching ? 360 : 0))
                    .animation(
                        isFetching
                            ? .linear(duration: 0.9).repeatForever(autoreverses: false)
                            : .easeOut(duration: 0.2),
                        value: isFetching
                    )
                Text("Refresh")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.primary.opacity(backgroundOpacity))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color.primary.opacity(borderOpacity), lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle(isPressed: $isPressed))
        .disabled(isFetching)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .animation(.easeOut(duration: 0.08), value: isPressed)
    }

    private var foregroundColor: Color {
        if isFetching { return .secondary }
        if isPressed || isHovering { return .primary }
        return .primary.opacity(0.85)
    }

    private var backgroundOpacity: Double {
        if isFetching { return 0.04 }
        if isPressed { return 0.14 }
        if isHovering { return 0.08 }
        return 0.04
    }

    private var borderOpacity: Double {
        if isPressed { return 0.18 }
        if isHovering { return 0.12 }
        return 0.08
    }
}

private struct PressableButtonStyle: ButtonStyle {
    @Binding var isPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .onChange(of: configuration.isPressed) { _, pressed in
                isPressed = pressed
            }
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



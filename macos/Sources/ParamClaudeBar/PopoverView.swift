import SwiftUI
import Charts

struct PopoverView: View {
    @ObservedObject var service: UsageService
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
        VStack(spacing: 16) {
            Text("Claude Usage")
                .font(.headline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)

            VStack(spacing: 12) {
                CompactWindowRow(
                    label: "5h",
                    bucket: service.usage?.fiveHour,
                    tint: Theme.fiveHourTint(forFraction:)
                )
                CompactWindowRow(
                    label: "7d",
                    bucket: service.usage?.sevenDay,
                    tint: Theme.sevenDayTint(forFraction:)
                )
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

// MARK: - Compact window row (label + inline %, slim outlined bar)

private struct CompactWindowRow: View {
    let label: String
    let bucket: UsageBucket?
    let tint: (Double) -> Color

    private var fraction: Double {
        max(0, min(1, (bucket?.utilization ?? 0) / 100.0))
    }
    private var hasData: Bool { bucket?.utilization != nil }
    private var pctInt: Int { Int(round(bucket?.utilization ?? 0)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(hasData ? "\(label): \(pctInt)%" : "\(label): —")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .contentTransition(.numericText())

            SlimBar(fraction: fraction, tint: tint(fraction))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.25), value: fraction)
    }
}

private struct SlimBar: View {
    let fraction: Double
    let tint: Color
    private let height: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.20), lineWidth: 1)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(tint)
                    .frame(width: max(fraction > 0 ? height * 0.6 : 0, geo.size.width * fraction))
                    .padding(1)
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



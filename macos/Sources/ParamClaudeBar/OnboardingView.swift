import SwiftUI

/// Standalone onboarding window per SPEC §13. A four-step flow:
/// Welcome → Sign in → Notifications → Done.
struct OnboardingView: View {
    @ObservedObject var service: UsageService
    @ObservedObject var notificationService: NotificationService
    var onFinish: () -> Void

    @State private var step: OnboardingStep = .welcome

    enum OnboardingStep: Int, CaseIterable {
        case welcome, signIn, notifications, done
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                content
                    .id(step)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 36)
            .padding(.top, 36)

            footer
                .padding(.horizontal, 28)
                .padding(.bottom, 22)
        }
        .frame(width: 520, height: 400)
        .background(.ultraThickMaterial)
        .onChange(of: service.isAuthenticated) { _, isAuthenticated in
            if isAuthenticated, step == .signIn {
                advance(to: .notifications)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome: welcomePane
        case .signIn: signInPane
        case .notifications: notificationsPane
        case .done: donePane
        }
    }

    // MARK: - Panes

    @ViewBuilder
    private var welcomePane: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Welcome to")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("ParamClaudeBar")
                .font(.system(size: 36, weight: .semibold, design: .rounded))
            Text("Keep an eye on your Claude usage from the menu bar — at a glance, with notifications when you're getting close to a limit.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var signInPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Sign in")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
            Text("Authorise the app with your Claude account so it can read your usage. Nothing is sent anywhere except the Anthropic API.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if service.isAwaitingCode {
                CodePasteback(service: service)
                    .padding(.top, 4)
            }

            if let error = service.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Theme.error)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var notificationsPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Notifications")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
            Text("Get a quiet macOS notification when you cross your warning or critical threshold, or when the burn rate is about to push you past a limit. You can change this any time in Settings.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                bullet(text: "Warning at \(notificationService.warningPercent)%")
                bullet(text: "Critical at \(notificationService.criticalPercent)%")
                bullet(text: "Burn-rate alert")
            }
            .padding(.top, 4)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var donePane: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("You're all set")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
            Text("Look for the dual-ring icon in your menu bar. Click it any time for the full picture.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 14) {
            StepDots(current: step.rawValue, total: OnboardingStep.allCases.count)

            Spacer()

            if step == .signIn, !service.isAwaitingCode, !service.isAuthenticated {
                Button("Skip for now") { advance(to: .notifications) }
                    .buttonStyle(.borderless)
            } else if step == .notifications {
                Button("Skip") { advance(to: .done) }
                    .buttonStyle(.borderless)
            }

            primaryButton
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch step {
        case .welcome:
            Button("Continue") { advance(to: .signIn) }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        case .signIn:
            if service.isAwaitingCode {
                EmptyView()
            } else if service.isAuthenticated {
                Button("Continue") { advance(to: .notifications) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            } else {
                Button("Sign in with Claude") { service.startOAuthFlow() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        case .notifications:
            Button("Allow notifications") {
                notificationService.requestPermissionIfNeeded()
                advance(to: .done)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        case .done:
            Button("Open the menu bar") { onFinish() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
    }

    private func bullet(text: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(.tint)
                .frame(width: 5, height: 5)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.primary.opacity(0.05), in: Capsule())
    }

    private func advance(to step: OnboardingStep) {
        withAnimation(.easeInOut(duration: 0.25)) {
            self.step = step
        }
    }
}

private struct CodePasteback: View {
    @ObservedObject var service: UsageService
    @State private var code = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Paste the code from your browser:")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
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

private struct StepDots: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                Circle()
                    .fill(i == current ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 6, height: 6)
                    .animation(.easeInOut(duration: 0.2), value: current)
            }
        }
    }
}

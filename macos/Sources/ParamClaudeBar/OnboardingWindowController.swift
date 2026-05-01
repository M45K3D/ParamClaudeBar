import AppKit
import SwiftUI

/// Imperative AppKit controller used to present the onboarding flow as
/// a real titled window outside the MenuBarExtra popover, per SPEC §13.
@MainActor
final class OnboardingWindowController {
    static let shared = OnboardingWindowController()

    private var window: NSWindow?

    static func show(
        service: UsageService,
        notificationService: NotificationService,
        settings: SettingsStore
    ) {
        shared.present(
            service: service,
            notificationService: notificationService,
            settings: settings
        )
    }

    private func present(
        service: UsageService,
        notificationService: NotificationService,
        settings: SettingsStore
    ) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = OnboardingView(
            service: service,
            notificationService: notificationService,
            onFinish: { [weak self] in
                UserDefaults.standard.set(true, forKey: "setupComplete")
                self?.dismiss()
            }
        )
        .preferredColorScheme(settings.appearanceTheme.preferredColorScheme)

        let host = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: host)
        window.title = "Welcome to ParamClaudeBar"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = WindowDelegate.shared

        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    fileprivate func dismiss() {
        window?.orderOut(nil)
        window = nil
    }
}

private final class WindowDelegate: NSObject, NSWindowDelegate {
    static let shared = WindowDelegate()

    func windowWillClose(_ notification: Notification) {
        UserDefaults.standard.set(true, forKey: "setupComplete")
        Task { @MainActor in
            OnboardingWindowController.shared.dismiss()
        }
    }
}

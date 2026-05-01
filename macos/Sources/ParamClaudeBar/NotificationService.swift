import Foundation
@preconcurrency import UserNotifications

private let resetIsoFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

private final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

/// User-configurable notification preferences and the runtime that decides
/// when to actually fire a notification, with debouncing per SPEC §10.
@MainActor
class NotificationService: ObservableObject {
    @Published var warningEnabled: Bool {
        didSet { defaults.set(warningEnabled, forKey: K.warningEnabled) }
    }
    @Published var criticalEnabled: Bool {
        didSet { defaults.set(criticalEnabled, forKey: K.criticalEnabled) }
    }
    @Published var burnRateEnabled: Bool {
        didSet { defaults.set(burnRateEnabled, forKey: K.burnRateEnabled) }
    }
    @Published var resetEnabled: Bool {
        didSet { defaults.set(resetEnabled, forKey: K.resetEnabled) }
    }
    @Published var warningPercent: Int {
        didSet { defaults.set(warningPercent, forKey: K.warningPercent) }
    }
    @Published var criticalPercent: Int {
        didSet { defaults.set(criticalPercent, forKey: K.criticalPercent) }
    }

    private let defaults: UserDefaults
    private let delegate = NotificationDelegate()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.warningEnabled = (defaults.object(forKey: K.warningEnabled) as? Bool) ?? true
        self.criticalEnabled = (defaults.object(forKey: K.criticalEnabled) as? Bool) ?? true
        self.burnRateEnabled = (defaults.object(forKey: K.burnRateEnabled) as? Bool) ?? true
        self.resetEnabled = defaults.bool(forKey: K.resetEnabled)
        self.warningPercent = (defaults.object(forKey: K.warningPercent) as? Int) ?? 75
        self.criticalPercent = (defaults.object(forKey: K.criticalPercent) as? Int) ?? 90
        if Self.isRunningAsApp {
            UNUserNotificationCenter.current().delegate = delegate
        }
    }

    nonisolated private static var isRunningAsApp: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    // MARK: - Permissions

    func requestPermissionIfNeeded() {
        guard Self.isRunningAsApp else { return }
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: - Public API used by UsageService

    /// Single entry point invoked after every successful poll. Decides
    /// which notifications (if any) should fire, applying the §10.2
    /// per-window debouncing rules.
    func evaluate(
        pct5h: Double,
        pct7d: Double,
        reset5h: Date?,
        reset7d: Date?,
        burnRate5h: BurnRateProjection?
    ) {
        detectResetAndClearState(window: "5h", currentReset: reset5h)
        detectResetAndClearState(window: "7d", currentReset: reset7d)

        if warningEnabled {
            crossThreshold(
                window: "5h", pct: pct5h, reset: reset5h,
                threshold: warningPercent, kind: "warning", title: "Approaching limit"
            )
            crossThreshold(
                window: "7d", pct: pct7d, reset: reset7d,
                threshold: warningPercent, kind: "warning", title: "Approaching limit"
            )
        }

        if criticalEnabled {
            crossThreshold(
                window: "5h", pct: pct5h, reset: reset5h,
                threshold: criticalPercent, kind: "critical", title: "Limit nearly reached"
            )
            crossThreshold(
                window: "7d", pct: pct7d, reset: reset7d,
                threshold: criticalPercent, kind: "critical", title: "Limit nearly reached"
            )
        }

        if burnRateEnabled, let burnRate5h, let projected = burnRate5h.projectedHitTime {
            let lastKey = K.lastFire("burnRate", "5h")
            if defaults.string(forKey: lastKey) == nil {
                let secondsUntilHit = projected.timeIntervalSinceNow
                if secondsUntilHit > 0 && secondsUntilHit <= 30 * 60 {
                    let minutes = Int(round(secondsUntilHit / 60))
                    sendNotification(
                        identifier: "burn-rate-5h",
                        title: "Limit imminent",
                        body: "At current pace you'll hit the 5-hour limit in ~\(minutes) minutes."
                    )
                    defaults.set(resetIsoFormatter.string(from: Date()), forKey: lastKey)
                }
            }
        }
    }

    func sendTestNotification() {
        requestPermissionIfNeeded()
        sendNotification(
            identifier: "test",
            title: "ParamClaudeBar",
            body: "Test notification — your alerts are wired up."
        )
    }

    // MARK: - Internals

    private func detectResetAndClearState(window: String, currentReset: Date?) {
        guard let currentReset else { return }
        let knownKey = K.knownReset(window)
        let lastKnown = defaults.string(forKey: knownKey).flatMap(resetIsoFormatter.date(from:))

        defer {
            defaults.set(resetIsoFormatter.string(from: currentReset), forKey: knownKey)
        }

        guard let lastKnown else { return }
        guard currentReset > lastKnown else { return }

        if resetEnabled {
            let windowName = window == "5h" ? "5-hour" : "7-day"
            sendNotification(
                identifier: "reset-\(window)",
                title: "Quota reset",
                body: "Your \(windowName) window has reset."
            )
        }

        defaults.removeObject(forKey: K.lastFire("warning", window))
        defaults.removeObject(forKey: K.lastFire("critical", window))
        if window == "5h" {
            defaults.removeObject(forKey: K.lastFire("burnRate", "5h"))
        }
    }

    private func crossThreshold(
        window: String,
        pct: Double,
        reset: Date?,
        threshold: Int,
        kind: String,
        title: String
    ) {
        guard threshold > 0, pct >= Double(threshold) else { return }

        let lastKey = K.lastFire(kind, window)
        guard defaults.string(forKey: lastKey) == nil else { return }

        let resetText = reset.map(formatResetClock) ?? "soon"
        let windowName = window == "5h" ? "5-hour" : "7-day"
        sendNotification(
            identifier: "\(kind)-\(window)",
            title: title,
            body: "\(windowName) usage at \(Int(round(pct)))%. Resets at \(resetText)."
        )
        defaults.set(resetIsoFormatter.string(from: Date()), forKey: lastKey)
    }

    private func sendNotification(identifier: String, title: String, body: String) {
        guard Self.isRunningAsApp else {
            print("[Notification] \(title): \(body) (skipped — not running inside app bundle)")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("[Notification] Failed to deliver: \(error)")
            }
        }
    }

    private enum K {
        static let warningEnabled = "notify.warningEnabled"
        static let criticalEnabled = "notify.criticalEnabled"
        static let burnRateEnabled = "notify.burnRateEnabled"
        static let resetEnabled = "notify.resetEnabled"
        static let warningPercent = "notify.warningPercent"
        static let criticalPercent = "notify.criticalPercent"

        static func lastFire(_ kind: String, _ window: String) -> String {
            "notify.last.\(kind).\(window)"
        }
        static func knownReset(_ window: String) -> String {
            "notify.knownReset.\(window)"
        }
    }
}

private func formatResetClock(_ date: Date) -> String {
    date.formatted(.dateTime.hour().minute().locale(.init(identifier: "en_GB")))
}

// MARK: - Pure helpers (kept for tests of the threshold logic)

struct ThresholdCross: Equatable {
    let window: String
    let kind: String
    let pct: Int
}

/// Pure decision function: returns the alerts that *would* fire for the
/// given inputs, ignoring any persisted debounce state. Used by tests.
func threshholdCrosses(
    warningEnabled: Bool,
    criticalEnabled: Bool,
    warningPercent: Int,
    criticalPercent: Int,
    pct5h: Double,
    pct7d: Double
) -> [ThresholdCross] {
    var alerts: [ThresholdCross] = []
    if warningEnabled {
        if pct5h >= Double(warningPercent) {
            alerts.append(.init(window: "5h", kind: "warning", pct: Int(round(pct5h))))
        }
        if pct7d >= Double(warningPercent) {
            alerts.append(.init(window: "7d", kind: "warning", pct: Int(round(pct7d))))
        }
    }
    if criticalEnabled {
        if pct5h >= Double(criticalPercent) {
            alerts.append(.init(window: "5h", kind: "critical", pct: Int(round(pct5h))))
        }
        if pct7d >= Double(criticalPercent) {
            alerts.append(.init(window: "7d", kind: "critical", pct: Int(round(pct7d))))
        }
    }
    return alerts
}

import Foundation
import SwiftUI

/// How the menu bar widget renders itself, per SPEC §7.1.
enum MenuBarDisplayMode: String, CaseIterable, Identifiable {
    case iconOnly
    case iconAndPercentage
    case percentageOnly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .iconOnly: return "Icon"
        case .iconAndPercentage: return "Icon + %"
        case .percentageOnly: return "% only"
        }
    }
}

/// User-selectable interface theme, per SPEC §9.2.
enum AppearanceTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Centralized observable wrapper around the persisted user preferences.
///
/// Phase 4 introduces the full set of keys described in SPEC §9 so later
/// phases can read/write them without scattering UserDefaults calls. The
/// menu bar display mode is the only setting actively wired up at this
/// stage — the rest persist their value but are consumed in later phases.
@MainActor
final class SettingsStore: ObservableObject {
    private let defaults: UserDefaults

    @Published var menuBarDisplayMode: MenuBarDisplayMode {
        didSet { defaults.set(menuBarDisplayMode.rawValue, forKey: Keys.menuBarDisplayMode) }
    }

    @Published var appearanceTheme: AppearanceTheme {
        didSet { defaults.set(appearanceTheme.rawValue, forKey: Keys.appearanceTheme) }
    }

    @Published var showBurnRateHint: Bool {
        didSet { defaults.set(showBurnRateHint, forKey: Keys.showBurnRateHint) }
    }

    @Published var useMonochromeIcon: Bool {
        didSet { defaults.set(useMonochromeIcon, forKey: Keys.useMonochromeIcon) }
    }

    @Published var notifyWarningEnabled: Bool {
        didSet { defaults.set(notifyWarningEnabled, forKey: Keys.notifyWarningEnabled) }
    }

    @Published var notifyCriticalEnabled: Bool {
        didSet { defaults.set(notifyCriticalEnabled, forKey: Keys.notifyCriticalEnabled) }
    }

    @Published var notifyBurnRateEnabled: Bool {
        didSet { defaults.set(notifyBurnRateEnabled, forKey: Keys.notifyBurnRateEnabled) }
    }

    @Published var notifyResetEnabled: Bool {
        didSet { defaults.set(notifyResetEnabled, forKey: Keys.notifyResetEnabled) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let storedMode = defaults.string(forKey: Keys.menuBarDisplayMode)
            .flatMap(MenuBarDisplayMode.init(rawValue:))
        self.menuBarDisplayMode = storedMode ?? .iconAndPercentage

        let storedTheme = defaults.string(forKey: Keys.appearanceTheme)
            .flatMap(AppearanceTheme.init(rawValue:))
        self.appearanceTheme = storedTheme ?? .system

        self.showBurnRateHint = defaults.bool(forKey: Keys.showBurnRateHint)
        self.useMonochromeIcon = defaults.bool(forKey: Keys.useMonochromeIcon)

        self.notifyWarningEnabled = (defaults.object(forKey: Keys.notifyWarningEnabled) as? Bool) ?? true
        self.notifyCriticalEnabled = (defaults.object(forKey: Keys.notifyCriticalEnabled) as? Bool) ?? true
        self.notifyBurnRateEnabled = (defaults.object(forKey: Keys.notifyBurnRateEnabled) as? Bool) ?? true
        self.notifyResetEnabled = defaults.bool(forKey: Keys.notifyResetEnabled)
    }

    private enum Keys {
        static let menuBarDisplayMode = "menuBarDisplayMode"
        static let appearanceTheme = "appearanceTheme"
        static let showBurnRateHint = "showBurnRateHint"
        static let useMonochromeIcon = "useMonochromeIcon"
        static let notifyWarningEnabled = "notifyWarningEnabled"
        static let notifyCriticalEnabled = "notifyCriticalEnabled"
        static let notifyBurnRateEnabled = "notifyBurnRateEnabled"
        static let notifyResetEnabled = "notifyResetEnabled"
    }
}

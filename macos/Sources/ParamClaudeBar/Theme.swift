import SwiftUI

/// Centralized colour and style tokens.
///
/// Phase 2 codifies the values already used across the app so that later
/// phases (§7.3 ring palette, §8 popover redesign) can evolve them in one
/// place. Preserving the existing visuals is intentional — this commit
/// adds tokens without changing any pixels.
enum Theme {
    /// Accent for the 5-hour window line, point marks, and tooltip indicator.
    static let fiveHourAccent: Color = .blue

    /// Accent for the 7-day window line, point marks, and tooltip indicator.
    static let sevenDayAccent: Color = .orange

    /// Tint for the dollar-denominated extra-usage progress bar.
    static let extraUsageAccent: Color = .blue

    /// Inline error text accent (sign-in failures, fetch errors, updater errors).
    static let error: Color = .red

    /// Inline warning text accent (e.g. discouraged polling intervals).
    static let warning: Color = .orange

    /// Tint applied to a window-utilization progress bar based on its fill fraction (0–1).
    static func progressTint(forFraction fraction: Double) -> Color {
        switch fraction {
        case ..<0.60: return .green
        case 0.60..<0.80: return .yellow
        default: return .red
        }
    }

    /// 5-hour window palette per SPEC §7.3.
    static func fiveHourTint(forFraction fraction: Double) -> Color {
        switch fraction {
        case ..<0.60: return Color(nsColor: .systemGreen)
        case 0.60..<0.85: return Color(nsColor: .systemOrange)
        default: return Color(nsColor: .systemRed)
        }
    }

    /// 7-day window palette per SPEC §7.3.
    static func sevenDayTint(forFraction fraction: Double) -> Color {
        switch fraction {
        case ..<0.60: return Color(nsColor: .systemBlue)
        case 0.60..<0.85: return Color(nsColor: .systemPurple)
        default: return Color(nsColor: .systemPink)
        }
    }
}

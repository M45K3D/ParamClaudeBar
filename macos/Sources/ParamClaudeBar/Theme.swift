import SwiftUI

/// Centralized colour and style tokens.
enum Theme {
    /// Inline error text accent (sign-in failures, fetch errors, updater errors).
    static let error: Color = .red

    /// Inline warning text accent (e.g. discouraged polling intervals).
    static let warning: Color = .orange

    /// The popover's card surface. The popover is always dark regardless of the
    /// system appearance, so this is a fixed near-black rather than a semantic
    /// colour.
    static let popoverSurface = Color(red: 0.086, green: 0.086, blue: 0.094)

    /// Hairline border drawn around the popover card.
    static let popoverBorder = Color.white.opacity(0.09)

    /// Severity tint for a usage bar, from its 0–1 fill fraction. One palette is
    /// used for every window so a low number always reads green and a high one
    /// always reads red, whichever row it is on.
    static func usageTint(forFraction fraction: Double) -> Color {
        switch fraction {
        case ..<0.60: return Color(nsColor: .systemGreen)
        case 0.60..<0.85: return Color(nsColor: .systemOrange)
        default: return Color(nsColor: .systemRed)
        }
    }
}

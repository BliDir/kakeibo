import SwiftUI

/// Colors from the "Kakeibo iOS App Screens" canvas.
///
/// Temporary: T-04 replaces these with color assets that have dark-mode variants.
/// Views use these names, never literal colors.
enum Theme {
    /// 藍 indigo accent.
    static let accent = Color(red: 0x2B / 255, green: 0x47 / 255, blue: 0x85 / 255)
    static let accentTint = Color(red: 0xE3 / 255, green: 0xE9 / 255, blue: 0xF5 / 255)
    /// Cool grey ground behind the reading screen.
    static let ground = Color(red: 0xE4 / 255, green: 0xE7 / 255, blue: 0xEC / 255)
    static let surface = Color.white
    static let text = Color(red: 0x1A / 255, green: 0x1F / 255, blue: 0x2B / 255)
    static let secondaryText = Color(red: 0x5F / 255, green: 0x66 / 255, blue: 0x76 / 255)
    static let border = Color(red: 0xDA / 255, green: 0xDD / 255, blue: 0xE3 / 255)
    static let divider = Color(red: 0xEC / 255, green: 0xEE / 255, blue: 0xF2 / 255)
    static let pending = Color(red: 0xC9 / 255, green: 0xCD / 255, blue: 0xD5 / 255)
    static let success = Color(red: 0x2F / 255, green: 0x7A / 255, blue: 0x4F / 255)
    /// 朱 vermilion, for destructive actions and errors.
    static let destructive = Color(red: 0xC2 / 255, green: 0x3B / 255, blue: 0x22 / 255)
    /// Light ground behind the ledger and review screens.
    static let groundLight = Color(red: 0xEE / 255, green: 0xF0 / 255, blue: 0xF3 / 255)
    /// Input fill.
    static let field = Color(red: 0xF6 / 255, green: 0xF7 / 255, blue: 0xF9 / 255)

    /// "Check this field": amber border, fill and text.
    static let warning = Color(red: 0xC9 / 255, green: 0x8A / 255, blue: 0x1A / 255)
    static let warningFill = Color(red: 0xFF / 255, green: 0xF4 / 255, blue: 0xDF / 255)
    static let warningText = Color(red: 0x7A / 255, green: 0x4E / 255, blue: 0x00 / 255)

    static let reducedRateFill = Color(red: 0xE2 / 255, green: 0xEF / 255, blue: 0xE6 / 255)
    static let reducedRateText = Color(red: 0x2D / 255, green: 0x6A / 255, blue: 0x45 / 255)
    static let standardRateText = Color(red: 0x4A / 255, green: 0x50 / 255, blue: 0x5C / 255)
}

import KakeiboCore

extension ExpenseCategory {
    /// Category dot color from the canvas. Temporary until T-04's category styling.
    var color: Color {
        switch self {
        case .groceries: Color(red: 0x3F / 255, green: 0x8A / 255, blue: 0x5C / 255)
        case .dining: Color(red: 0xC9 / 255, green: 0x6B / 255, blue: 0x2C / 255)
        case .household: Color(red: 0x8A / 255, green: 0x6B / 255, blue: 0xB8 / 255)
        case .transport: Color(red: 0x2F / 255, green: 0x74 / 255, blue: 0xB5 / 255)
        case .kids: Color(red: 0xD0 / 255, green: 0x54 / 255, blue: 0x8A / 255)
        case .health: Color(red: 0x2C / 255, green: 0x9A / 255, blue: 0x9A / 255)
        case .shopping: Color(red: 0xB0 / 255, green: 0x8A / 255, blue: 0x1E / 255)
        case .utilities: Color(red: 0x5D / 255, green: 0x6B / 255, blue: 0x82 / 255)
        case .other: Color(red: 0x8C / 255, green: 0x8F / 255, blue: 0x96 / 255)
        }
    }
}

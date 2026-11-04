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
}

import SwiftUI
import UIKit

/// The six design tokens, light/dark. Shared because the widget extension renders the
/// same capacity ring as the app and the icon, and a second copy of these hex values
/// is a second place for them to drift.
///
/// The domain-specific tints — exclusion verdicts, trace kinds — stay in the app's own
/// `Palette.swift`, because they extend types the extension has no business importing.
enum Palette {
    static let surface  = adaptive(light: 0xE5E4E2, dark: 0x0A0A0A)
    static let ink      = adaptive(light: 0x0A0A0A, dark: 0xE5E4E2)
    static let accent   = adaptive(light: 0x536878, dark: 0x7C93A6)
    static let safe     = adaptive(light: 0x4A6147, dark: 0xADBDAB)
    static let excluded = adaptive(light: 0x6F1D1B, dark: 0xC4756F)
    static let unknown  = adaptive(light: 0x7A5C15, dark: 0xD9A845)
    static let muted    = adaptive(light: 0x6B6B6B, dark: 0x9A9A9A)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: Double((rgb >> 16) & 0xFF) / 255.0,
                  green: Double((rgb >> 8) & 0xFF) / 255.0,
                  blue: Double(rgb & 0xFF) / 255.0,
                  alpha: 1.0)
    }
}

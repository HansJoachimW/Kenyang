import SwiftUI
import UIKit

/// The colour tokens, light and dark, shared by the app and the widget extension.
enum Palette {
    static let surface  = adaptive(light: 0xE5E4E2, dark: 0x0A0A0A)
    static let raised   = adaptive(light: 0xEFEEEC, dark: 0x1A1A1A)
    static let ink      = adaptive(light: 0x0A0A0A, dark: 0xE5E4E2)
    static let accent   = adaptive(light: 0x536878, dark: 0x7C93A6)
    static let safe     = adaptive(light: 0x4A6147, dark: 0xADBDAB)
    static let excluded = adaptive(light: 0x6F1D1B, dark: 0xC4756F)
    static let unknown  = adaptive(light: 0x7A5C15, dark: 0xD9A845)
    static let muted    = adaptive(light: 0x5F5F5F, dark: 0x9A9A9A)

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

import SwiftUI
import UIKit

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

extension ExclusionVerdict {
    var tint: Color {
        switch self {
        case .safe:     Palette.safe
        case .excluded: Palette.excluded
        case .unknown:  Palette.unknown
        }
    }

    var word: String {
        switch self {
        case .safe:     "safe"
        case .excluded: "excluded"
        case .unknown:  "ask staff"
        }
    }
}

extension TraceKind {
    var tint: Color {
        switch self {
        case .modelFailure: Palette.muted
        default:            Palette.accent
        }
    }
}

struct VerdictBadge: View {
    let verdict: ExclusionVerdict

    var body: some View {
        Text(verdict.word)
            .font(.caption2.weight(.medium))
            .foregroundStyle(verdict.tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(verdict.tint.opacity(0.12), in: Capsule())
            .accessibilityLabel(verdict.word)
    }
}

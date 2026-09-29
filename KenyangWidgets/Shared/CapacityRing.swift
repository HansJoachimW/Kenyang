import SwiftUI

/// The capacity glyph — the one mark shared by the app icon, the lock-screen bar, the
/// widget and all three Island presentations.
///
/// Geometry follows the design record: a full track, and an arc that starts at 12
/// o'clock and runs clockwise for the fraction remaining, with square ends. The icon is
/// this glyph frozen at two thirds — the only difference between them is that this one
/// tracks capacity. A full ring and a nearly-empty one differ by arc length, not by
/// colour alone.
struct CapacityRing: View {
    /// 0…1 remaining. Clamped, because a capacity model that has drifted must not be
    /// able to draw an arc longer than the ring.
    let fraction: Double
    var lineWidth: CGFloat = 5

    /// The icon's track: Blue Slate Light at this opacity over Onyx, from the design PDF.
    private static let trackOpacity = 0.2784

    var body: some View {
        ZStack {
            arc(1).foregroundStyle(Palette.accent.opacity(Self.trackOpacity))
            arc(fraction.clamped01).foregroundStyle(Palette.accent)
        }
        // `trim` starts at 3 o'clock; this starts the arc at 12.
        .rotationEffect(.degrees(-90))
        .accessibilityElement()
        .accessibilityLabel("Capacity remaining")
        .accessibilityValue("\(Int(fraction.clamped01 * 100)) percent")
    }

    private func arc(_ portion: Double) -> some View {
        Circle()
            .trim(from: 0, to: portion)
            .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
            .padding(lineWidth / 2)
    }
}

private extension Double {
    var clamped01: Double { Swift.max(0, Swift.min(1, self)) }
}

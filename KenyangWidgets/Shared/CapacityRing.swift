import SwiftUI

/// The capacity glyph — the one mark shared by the app icon, the lock-screen bar, the
/// widget and all three Island presentations.
///
/// The icon's arc is fixed; this one tracks capacity, which is the only difference
/// between them. Geometry follows the design: a 240° sweep with the gap centred at
/// 12 o'clock, so a full ring and a nearly-empty one differ by arc length and not by
/// colour alone.
struct CapacityRing: View {
    /// 0…1 remaining. Clamped, because a capacity model that has drifted must not be
    /// able to draw an arc longer than the ring.
    let fraction: Double
    var lineWidth: CGFloat = 5

    private static let sweep = 240.0 / 360.0

    var body: some View {
        ZStack {
            arc(Self.sweep).foregroundStyle(Palette.muted.opacity(0.25))
            arc(Self.sweep * fraction.clamped01).foregroundStyle(Palette.accent)
        }
        // `trim` starts at 3 o'clock; this puts the gap at the top.
        .rotationEffect(.degrees(150))
        .accessibilityElement()
        .accessibilityLabel("Capacity remaining")
        .accessibilityValue("\(Int(fraction.clamped01 * 100)) percent")
    }

    private func arc(_ portion: Double) -> some View {
        Circle()
            .trim(from: 0, to: portion)
            .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .padding(lineWidth / 2)
    }
}

private extension Double {
    var clamped01: Double { Swift.max(0, Swift.min(1, self)) }
}

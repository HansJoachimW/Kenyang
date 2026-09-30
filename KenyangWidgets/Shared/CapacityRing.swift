import SwiftUI

/// Room left, as the app icon's ring: a faint track and an arc from 12 o'clock running
/// clockwise. It empties as the diner eats.
struct CapacityRing: View {
    let fraction: Double
    var lineWidth: CGFloat = 5

    private static let trackOpacity = 0.2784

    var body: some View {
        ZStack {
            arc(1).foregroundStyle(Palette.accent.opacity(Self.trackOpacity))
            arc(fraction.clamped01).foregroundStyle(Palette.accent)
        }
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

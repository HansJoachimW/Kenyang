import SwiftUI

/// Stopping is the app working, so it uses the accent, never red, and "keep going" is
/// always one plain tap away.
struct StopView: View {
    let model: MealViewModel
    let reason: StopReason
    @ScaledMetric(relativeTo: .largeTitle) private var headlineSize: CGFloat = 40
    @State private var isAskingWhy = false

    private var visit: Visit? { model.session.visit }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SectionLabel("Worked out from your numbers, not the AI")
                    Text(headline)
                        .font(.system(size: headlineSize, weight: .bold))
                        .foregroundStyle(Palette.ink)
                    Text(StopGuard.detail(for: reason)).foregroundStyle(Palette.ink)
                    Divider()
                    readings
                    if isAskingWhy {
                        whyItEnded
                    } else {
                        Text("Stated once, after the fact. It is not a reason to continue.")
                            .font(.caption)
                            .foregroundStyle(Palette.muted)
                    }
                }
                .padding(24)
            }
            if !isAskingWhy { actions }
        }
        .background(Palette.surface)
    }

    private var headline: String {
        switch reason {
        case .capacityExhausted: "Stop here."
        case .seatingTimeOver:   "Seating time is up."
        case .lastOrderPassed:   "Last order has passed."
        case .none:              "Ending here."
        }
    }

    @ViewBuilder
    private var readings: some View {
        if let visit {
            let capacity = CapacityEngine.state(for: visit)
            VStack(spacing: 8) {
                LabeledContent("Room left", value: capacity.fractionRemaining.formatted(.percent.precision(.fractionLength(0))))
                if reason == .capacityExhausted {
                    LabeledContent("Stop below", value: CapacityState.exhaustionThreshold.formatted(.percent))
                }
                if let minutes = visit.minutesRemaining {
                    LabeledContent("Seating left", value: "\(minutes) min")
                }
                LabeledContent("Rounds this meal", value: "\(model.session.round)")
                LabeledContent("Ordered", value: "Rp \(BreakEven.recovered(events: visit.tasteEvents).formatted(.number.precision(.fractionLength(0)))) of \(visit.pricePerHead.formatted(.number.precision(.fractionLength(0))))")
            }
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(Palette.ink)
        }
    }

    private var whyItEnded: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("One last question")
            Text("Why did the meal end?")
                .font(.title3.weight(.medium))
                .foregroundStyle(Palette.ink)
            FlowRow(spacing: 8) {
                ForEach(MealEnding.offered, id: \.self) { ending in
                    Button(ending.label) { model.endMeal(because: ending) }
                        .buttonStyle(.bordered)
                }
            }
            Text("Only \u{201C}I'm full\u{201D} tells Kenyang how much you can eat. The others mean you could have eaten more, so they can raise its estimate but never lower it.")
                .font(.caption)
                .foregroundStyle(Palette.muted)
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button { isAskingWhy = true } label: {
                Text("End the meal").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            HStack {
                Button("Keep going anyway", action: model.keepGoing)
                Spacer()
                Button("See why") { model.isShowingTrace = true }
            }
            .font(.subheadline)
        }
        .padding(24)
        .background(Palette.surface)
    }
}

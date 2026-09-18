import SwiftUI

/// Screen 6 — Stop. Unprompted, and in accent rather than red.
///
/// Red would file the app's proudest behaviour as an error. Weight and placement carry
/// the emphasis instead: 40 pt at the top of the screen with nothing competing.
///
/// **The threshold sits next to the reading.** The model chose `stop` zero times out of
/// three when handed exhausted capacity, so this fires deterministically — and printing
/// both numbers is what makes *"computed, not chosen"* checkable rather than claimed.
///
/// **"Keep going anyway" is plain, available text.** Not a button, not greyed out, not
/// behind a confirmation. The diner is in control, the app does not argue, and the
/// choice is not made to feel like a transgression.
struct StopView: View {
    let model: SessionViewModel

    @State private var askingReason = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("STOP GUARD · COMPUTED, NOT CHOSEN")
                        .font(.caption.weight(.semibold)).tracking(0.6)
                        .foregroundStyle(Palette.accent)

                    Text(headline)
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(Palette.ink)

                    Text(StopGuard.detail(for: model.stopReason))
                        .font(.body)
                        .foregroundStyle(Palette.ink)

                    Divider()
                    readings

                    if askingReason {
                        reasonQuestion
                    } else {
                        // Money is stated once, after the fact. It is not a reason to
                        // continue — the venue charges for what is left uneaten either way.
                        Text("Stated once, after the fact. It is not a reason to continue.")
                            .font(.caption)
                            .foregroundStyle(Palette.muted)
                    }
                }
                .padding(24)
            }
            actions
        }
        .background(Palette.surface)
    }

    // MARK: -

    private var headline: String {
        switch model.stopReason {
        case .capacityExhausted: "Stop here."
        case .seatingTimeOver:   "Seating time is up."
        case .lastOrderPassed:   "Last order has passed."
        case .none:              "Ending here."
        }
    }

    private var readings: some View {
        VStack(spacing: 8) {
            reading("Capacity remaining", percent(model.capacity.fractionRemaining))
            if model.stopReason == .capacityExhausted {
                reading("Threshold", percent(CapacityState.exhaustionThreshold))
            }
            if let minutes = model.minutesRemaining {
                reading("Seating left", "\(minutes) min")
            }
            reading("Rounds this meal", "\(model.roundIndex)")
            reading("Ordered", model.orderedAgainstCover)
        }
    }

    private func reading(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(Palette.ink)
            Spacer()
            Text(value).font(.subheadline.monospaced()).foregroundStyle(Palette.ink)
        }
    }

    private func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    /// The last of the meal's three permitted interruptions. Without it the capacity fit
    /// averages censored visits and biases itself downward, silently, worse the more the
    /// app is used.
    private var reasonQuestion: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ONE QUESTION, THE LAST OF THREE")
                .font(.caption.weight(.semibold)).tracking(0.6)
                .foregroundStyle(Palette.accent)
            Text("Why did the meal end?")
                .font(.title3.weight(.medium))
                .foregroundStyle(Palette.ink)

            FlowRow(spacing: 8) {
                ForEach(MealEnding.offered, id: \.self) { ending in
                    Button(ending.chipLabel) { model.endMeal(reason: ending) }
                        .font(.subheadline.weight(.medium))
                        .buttonStyle(.bordered)
                        .tint(Palette.accent)
                }
            }

            Text("A meal that ended on the clock is a lower bound on your capacity, not a reading of it. Kenyang will let it raise the estimate, never lower it.")
                .font(.caption)
                .foregroundStyle(Palette.muted)
        }
    }

    @ViewBuilder
    private var actions: some View {
        if askingReason {
            EmptyView()
        } else {
            VStack(spacing: 12) {
                Button { askingReason = true } label: {
                    Text("End the meal").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.accent)
                .controlSize(.large)

                HStack {
                    Button("Keep going anyway") { model.keepGoing() }
                    Spacer()
                    Button("Why this fired") { model.showTrace = true }
                }
                .font(.subheadline)
                .tint(Palette.accent)
            }
            .padding(24)
            .background(Palette.surface)
        }
    }
}

extension MealEnding {
    /// The four the diner is offered. `unknown` is what a meal gets when nobody asked —
    /// it is a state, not a choice.
    static var offered: [MealEnding] { [.fullness, .clock, .closing, .left] }

    var chipLabel: String {
        switch self {
        case .fullness: "full"
        case .clock:    "the clock"
        case .closing:  "closing"
        case .left:     "the group left"
        case .unknown:  "some other reason"
        }
    }
}

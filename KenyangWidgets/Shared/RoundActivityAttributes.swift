import ActivityKit
import Foundation

/// What the Live Activity carries, and the only type the widget extension needs from
/// the app.
///
/// **Primitives only, deliberately.** `ContentState` crosses a process boundary and is
/// re-encoded on every update, so referencing `CapacityState`, `RoundPlan` or anything
/// else from the model layer would drag the whole domain into the extension target to
/// render four numbers. Everything here is derived once, in `LiveActivityController`,
/// and shipped flat.
struct RoundActivityAttributes: ActivityAttributes {

    /// The four session states the design names. The bar and all three Island
    /// presentations render from this one value, which is what stops them drifting.
    enum Phase: String, Codable, Hashable, Sendable {
        case planning   // the agent is working out the round
        case active     // a round is accepted and being eaten
        case stopGuard  // a guardrail says the meal should end
        case degraded   // no model; planning from priors
    }

    struct ContentState: Codable, Hashable {
        var phase: Phase
        /// 0…1. The capacity ring — the one glyph shared by icon, bar, widget and Island.
        var fractionRemaining: Double
        var plateEstimate: Double
        var minutesToLastOrder: Int?
        var roundIndex: Int
        /// The next thing in plan order the diner has not logged yet.
        var nextTarget: String?
        /// Set only when the app has something earned to say — a stop reason or a
        /// degraded-mode explanation. Never a running total, never money, never a
        /// progress bar toward a ceiling that does not exist.
        var message: String?

        var platesText: String {
            plateEstimate < 0.75 ? "½ plate" : "\(String(format: "%.1f", plateEstimate)) plates"
        }

        var minutesText: String? {
            minutesToLastOrder.map { "\($0) min" }
        }
    }

    var venueName: String
}

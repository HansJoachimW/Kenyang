import ActivityKit
import Foundation

/// What the Live Activity shows. Plain values only, so the widget extension never needs
/// the app's model layer.
struct RoundActivityAttributes: ActivityAttributes {
    enum Phase: String, Codable, Hashable, Sendable {
        case planning, suggested, eating, roundDone, timeToStop

        var label: String {
            switch self {
            case .planning:   "planning"
            case .suggested:  "your next round"
            case .eating:     "eating"
            case .roundDone:  "round done"
            case .timeToStop: "time to stop"
            }
        }
    }

    struct IngredientQuestion: Codable, Hashable, Sendable {
        let dish: String
        let ingredient: String
    }

    struct ContentState: Codable, Hashable {
        var phase: Phase
        var fractionRemaining: Double
        var plateEstimate: Double
        var minutesToLastOrder: Int?
        var round: Int
        var nextDish: String?
        var message: String?
        var suggestion: [String] = []
        var question: IngredientQuestion?

        var platesText: String {
            plateEstimate < 0.75 ? "½ plate" : "\(plateEstimate.formatted(.number.precision(.fractionLength(1)))) plates"
        }

        var minutesText: String? {
            minutesToLastOrder.map { "\($0) min" }
        }
    }

    var venueName: String
}

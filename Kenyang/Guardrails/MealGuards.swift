import Foundation

enum StopReason: String, Sendable {
    case capacityExhausted, seatingTimeOver, lastOrderPassed, none
}

/// Stopping is worked out, never chosen by the AI: in testing it chose to stop 0 of 3
/// times when handed an exhausted capacity.
enum StopGuard {
    static let lastOrderMinutes = 15

    static func reason(capacity: CapacityState, minutesRemaining: Int?) -> StopReason {
        if capacity.isExhausted { return .capacityExhausted }
        guard let minutes = minutesRemaining else { return .none }
        if minutes <= 0 { return .seatingTimeOver }
        if minutes <= lastOrderMinutes { return .lastOrderPassed }
        return .none
    }

    static func reason(for visit: Visit) -> StopReason {
        reason(capacity: CapacityEngine.state(for: visit), minutesRemaining: visit.minutesRemaining)
    }

    /// What to say when the meal should stop, or nil when it shouldn't.
    static func stopMessage(for visit: Visit) -> String? {
        let reason = reason(for: visit)
        return reason == .none ? nil : message(for: reason)
    }

    static func shouldStop(capacity: CapacityState, minutesRemaining: Int?) -> Bool {
        reason(capacity: capacity, minutesRemaining: minutesRemaining) != .none
    }

    static func message(for reason: StopReason) -> String {
        switch reason {
        case .capacityExhausted: "You have about a quarter plate left. Spend it on something you already know is good, then stop."
        case .seatingTimeOver:   "Seating time is up."
        case .lastOrderPassed:   "Under fifteen minutes left. This is the last round."
        case .none:              ""
        }
    }

    static func detail(for reason: StopReason) -> String {
        switch reason {
        case .capacityExhausted: message(for: reason)
        case .seatingTimeOver:   "Whatever is already on the grill is the end of the meal."
        case .lastOrderPassed:   "Under fifteen minutes left. Anything ordered now is the last of it."
        case .none:              "Nothing is wrong. You decided, and that is reason enough."
        }
    }
}

/// Declines to plan when there is nothing to choose between.
enum TriageGuard {
    static let minimumDishes = 10
    static let declineMessage = "There isn't a decision problem here worth your attention: few items, one price tier, nothing to sequence. Just order what looks good."

    static func shouldDecline(menu: [DishSighting]) -> Bool {
        guard menu.count < minimumDishes else { return false }
        let hasTierSpread = Set(menu.map(\.tierRank)).count > 1
        let hasCategorySpread = Set(menu.map(\.category)).count > 2
        return !hasTierSpread && !hasCategorySpread
    }
}

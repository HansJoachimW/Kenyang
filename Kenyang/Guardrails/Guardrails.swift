import Foundation
import FoundationModels

struct ExclusionValidator {
    static func verdict(for sighting: DishSighting, exclusions: [String]) -> ExclusionVerdict {
        guard !exclusions.isEmpty else { return .safe }
        guard sighting.ingredientsKnown else { return .unknown }
        let haystack = (sighting.ingredients + [sighting.name]).map { $0.lowercased() }
        for term in exclusions.map({ $0.lowercased() }) where !term.isEmpty {
            if haystack.contains(where: { $0.contains(term) }) { return .excluded }
        }
        return .safe
    }

    static func partition(_ sightings: [DishSighting],
                          exclusions: [String]) -> (safe: [DishSighting],
                                                    excluded: [DishSighting],
                                                    unknown: [DishSighting]) {
        var safe: [DishSighting] = []
        var excluded: [DishSighting] = []
        var unknown: [DishSighting] = []
        for s in sightings {
            switch verdict(for: s, exclusions: exclusions) {
            case .safe:     safe.append(s)
            case .excluded: excluded.append(s)
            case .unknown:  unknown.append(s)
            }
        }
        return (safe, excluded, unknown)
    }
}

struct OutputValidator {
    static let forbidden = [
        "money's worth", "moneys worth", "get your money",
        "as much as possible", "unlimited", "maximise quantity",
        "maximize quantity", "eat more", "fill up on", "no limit",
        "stuff yourself", "worth the price by eating"
    ]

    static func isSafe(_ text: String) -> Bool {
        let lower = text.lowercased()
        return !forbidden.contains { lower.contains($0) }
    }

    static func sanitised(_ text: String, fallback: String) -> String {
        isSafe(text) ? text : fallback
    }
}

struct ConsistencyGuard {
    static func agrees(reason: String, move: RoundMove) -> Bool {
        let lower = reason.lowercased()
        let saysContradicted = lower.contains("contradict") || lower.contains("not supported")
            || lower.contains("elsewhere") || lower.contains("disprove")
        let saysSupported = lower.contains("support") || lower.contains("confirm")
            || lower.contains("holds")
        switch move {
        case .pivot:   return !saysSupported || saysContradicted
        case .exploit: return !saysContradicted
        }
    }
}

enum StopReason: String, Sendable {
    case capacityExhausted
    case seatingTimeOver
    case lastOrderPassed
    case none
}

struct StopGuard {
    static func reason(capacity: CapacityState, minutesRemaining: Int?) -> StopReason {
        if capacity.isExhausted { return .capacityExhausted }
        if let minutes = minutesRemaining {
            if minutes <= 0 { return .seatingTimeOver }
            if minutes <= 15 { return .lastOrderPassed }
        }
        return .none
    }

    static func shouldStop(capacity: CapacityState, minutesRemaining: Int?) -> Bool {
        reason(capacity: capacity, minutesRemaining: minutesRemaining) != .none
    }

    static func message(for reason: StopReason) -> String {
        switch reason {
        case .capacityExhausted: "You have about a quarter plate left. Spend it on something you already know is good, then stop."
        case .seatingTimeOver:   "Seating time is up."
        case .lastOrderPassed:   "Under fifteen minutes left — this is the last round."
        case .none:              ""
        }
    }
}

struct TriageGuard {
    static let minimumDishes = 10

    static func shouldDecline(sightings: [DishSighting]) -> Bool {
        guard sightings.count < minimumDishes else { return false }
        let hasTierSpread = Set(sightings.map(\.tierRank)).count > 1
        let hasCategorySpread = Set(sightings.map(\.category)).count > 2
        return !hasTierSpread && !hasCategorySpread
    }

    static let declineMessage = "There isn't a decision problem here worth your attention — few items, one price tier, nothing to sequence. Just order what looks good."
}

struct StatisticalGuard {
    static func canClaim(_ posterior: DishPosterior) -> Bool {
        posterior.sampleCount >= ValueEngine.minimumSamples
    }
}

struct LoopBudget {
    var maxRounds: Int = 6
    var callBudget: Int = 6
    var wallClockLimit: TimeInterval = 20
    private(set) var roundsUsed = 0
    private(set) var callsThisRound = 0

    mutating func beginRound() {
        roundsUsed += 1
        callsThisRound = 0
    }

    mutating func consumeCall() -> Bool {
        guard roundsUsed <= maxRounds, callsThisRound < callBudget else { return false }
        callsThisRound += 1
        return true
    }

    var isExhausted: Bool { roundsUsed > maxRounds }
}

struct AskBudget {
    static let perMeal = 3
    private(set) var spent = 0

    var remaining: Int { max(0, Self.perMeal - spent) }
    var hasBudget: Bool { remaining > 0 }

    mutating func spend() { spent += 1 }

    func isWorthAsking(informationValue: Double) -> Bool {
        guard hasBudget else { return false }
        let threshold = 0.35 + Double(spent) * 0.2
        return informationValue >= threshold
    }
}

enum ModelAvailability {
    case ready
    case downloading
    case notEnabled
    case unsupported

    var isReady: Bool { self == .ready }

    var explanation: String {
        switch self {
        case .ready:       ""
        case .downloading: "Apple Intelligence is still downloading. Planning with population priors until it finishes."
        case .notEnabled:  "Apple Intelligence is turned off. Planning with population priors — turn it on in Settings for reasoning and explanations."
        case .unsupported: "This device cannot run on-device models. Kenyang still plans rounds from priors and capacity maths, without narration."
        }
    }

    static func current() -> ModelAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .ready
        case .unavailable(let reason):
            switch reason {
            case .appleIntelligenceNotEnabled: return .notEnabled
            case .modelNotReady:               return .downloading
            default:                           return .unsupported
            }
        }
    }
}

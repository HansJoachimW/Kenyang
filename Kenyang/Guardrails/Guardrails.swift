import Foundation
import FoundationModels

struct ExclusionValidator {
    /// The verdict is reached per exclusion term, and the strictest one wins. A term is
    /// resolved three ways: the printed name settles it, a known ingredient list settles
    /// it, or the diner settles it after asking staff. Anything left unresolved makes
    /// the whole dish `unknown` — one open question is enough.
    static func verdict(for sighting: DishSighting, exclusions: [String]) -> ExclusionVerdict {
        let terms = normalised(exclusions)
        guard !terms.isEmpty else { return .safe }

        let name = sighting.name.lowercased()
        let listed = sighting.ingredients.map { $0.lowercased() }
        let cleared = Set(normalised(sighting.clearedTerms))

        var unresolved = false
        for term in terms {
            // The printed name is evidence in its own right. "Prawn Tempura" against an
            // exclusion of *prawn* is determinable with no ingredient list at all, and
            // checking it only after `ingredientsKnown` meant the one dish the app could
            // rule out for free came back `unknown`.
            if name.contains(term) { return .excluded }
            if listed.contains(where: { $0.contains(term) }) { return .excluded }
            if sighting.ingredientsKnown { continue }
            if cleared.contains(term) { continue }
            unresolved = true
        }
        return unresolved ? .unknown : .safe
    }

    /// The terms this dish still has no answer for — what the diner would have to ask
    /// staff about, and nothing more. Asking about a term already settled by the name
    /// or by a previous answer wastes the one thing the app is short of: the diner's
    /// patience mid-meal.
    static func unresolvedTerms(for sighting: DishSighting, exclusions: [String]) -> [String] {
        guard verdict(for: sighting, exclusions: exclusions) == .unknown else { return [] }
        let cleared = Set(normalised(sighting.clearedTerms))
        let name = sighting.name.lowercased()
        return normalised(exclusions).filter { term in
            !cleared.contains(term) && !name.contains(term)
        }
    }

    private static func normalised(_ terms: [String]) -> [String] {
        terms.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
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
    /// Why a call was refused. A refusal used to be a bare `false`, which meant the
    /// agent quietly fell back to deterministic defaults and the trace panel — the one
    /// four criteria rest on — showed nothing at all. A budget that stops the agent
    /// without saying so is indistinguishable from an agent that had nothing to say.
    enum Refusal: String, Sendable {
        case roundsExhausted    = "the round budget is spent"
        case callsExhausted     = "the call budget for this round is spent"
        case wallClockExpired   = "this round passed its wall-clock limit"
    }

    var maxRounds: Int = 6
    var callBudget: Int = 6
    var wallClockLimit: TimeInterval = 20
    private(set) var roundsUsed = 0
    private(set) var callsThisRound = 0
    private var roundStartedAt: Date = .now

    mutating func beginRound() {
        roundsUsed += 1
        callsThisRound = 0
        roundStartedAt = .now
    }

    /// `nil` means the call may proceed. Anything else is the reason it may not.
    mutating func consumeCall(now: Date = .now) -> Refusal? {
        if roundsUsed > maxRounds { return .roundsExhausted }
        if callsThisRound >= callBudget { return .callsExhausted }
        if now.timeIntervalSince(roundStartedAt) > wallClockLimit { return .wallClockExpired }
        callsThisRound += 1
        return nil
    }

    var isExhausted: Bool { roundsUsed > maxRounds }

    var spentDescription: String {
        "round \(roundsUsed)/\(maxRounds), call \(callsThisRound)/\(callBudget)"
    }
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

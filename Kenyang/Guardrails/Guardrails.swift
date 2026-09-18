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

    /// A claim has to say *where the value is*. The model sometimes returns a single
    /// word — "Unknown" — which decodes perfectly, passes every structural guard, and
    /// says nothing. Guided generation constrains shape, not meaning, so shape-valid
    /// and useless is a state the app has to catch itself.
    static func isSubstantive(_ text: String) -> Bool {
        text.split(whereSeparator: \.isWhitespace).count >= 4
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

    /// The longer form, for the stop screen. `message` is the one-liner Siri speaks and
    /// doubles as the headline there, so reusing it as the body printed the same
    /// sentence twice.
    static func detail(for reason: StopReason) -> String {
        switch reason {
        case .capacityExhausted: "You have about a quarter plate left. Spend it on something you already know is good, then stop."
        case .seatingTimeOver:   "Whatever is already on the grill is the end of the meal."
        case .lastOrderPassed:   "Under fifteen minutes left. Anything ordered now is the last of it."
        case .none:              "Nothing is wrong — you decided, and that is reason enough."
        }
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

    /// Generous on purpose. This exists to stop a runaway round, not to ration a normal
    /// one — and while it was declared and never read, nobody found out which it was.
    ///
    /// The 20 s it was written with came from a round believed to take ~36 s, which was
    /// the Simulator running ~3× slow. Enforcing it revealed the real cost: one decode
    /// failure on `hypothesise` plus its retry spent the whole budget, so `setIntent`
    /// was refused and the objective silently fell back to `balanced` — losing the one
    /// step where the model chooses policy. A normal device round with one retry is
    /// ~18 s, so the limit has to clear that with room, or the guardrail routinely eats
    /// the thing it is guarding.
    var wallClockLimit: TimeInterval = 45
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

/// Why a claim never reached the screen, and what the model actually wrote.
///
/// Three different authors, so three different treatments. A thin claim is the model
/// having nothing to say; a hallucination is a guardrail firing; a false positive is a
/// blunt filter being blunt. Collapsing them into one "unavailable" would hide which is
/// which, and which is which is the whole finding.
struct ClaimRejection: Sendable, Equatable {
    enum Layer: String, Sendable {
        case thin       = "CLAIM TOO THIN"
        case grounding  = "GROUNDING GUARD · LAYER 4"
        case stance     = "OUTPUT VALIDATOR · FAILED CLOSED"
    }

    let layer: Layer
    /// Shown struck through. The diner can see the app disagreeing with its own model,
    /// which is the point — hiding it would be the dishonest choice.
    let wrote: String
    let explanation: String
}

/// Layer 4. The model names a category that is not on tonight's menu, so nothing it
/// said about that category can be used.
///
/// `@Generable` constrains `category` to the enum, but `claim` is free text and the
/// model will happily write "the soup station" at a venue with no soup. Shape-valid and
/// ungrounded is a state only the app can catch.
struct GroundingGuard {
    static func ungroundedCategory(in claim: String, candidates: [DishSighting]) -> MenuCategory? {
        let present = Set(candidates.map(\.category))
        let spoken = words(in: claim)
        return MenuCategory.allCases.first { category in
            guard category != .unknown, !present.contains(category) else { return false }
            return !terms(for: category).isDisjoint(with: spoken)
        }
    }

    /// Matching on the display label as one string — "soup & broth" — meant the guard
    /// could never fire, because a model writes "the soup station", not the label
    /// verbatim. It compares words instead, drawn from both the label and the raw value.
    private static func terms(for category: MenuCategory) -> Set<String> {
        var terms = words(in: category.label)
        terms.insert(category.rawValue.lowercased())
        terms.remove("and")
        return terms
    }

    private static func words(in text: String) -> Set<String> {
        Set(text.lowercased()
            .split { !$0.isLetter }
            .map(String.init)
            .filter { $0.count >= 3 })
    }
}

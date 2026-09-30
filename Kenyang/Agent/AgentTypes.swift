import Foundation
import FoundationModels
import Observation

@Generable
struct ValueHypothesis: Sendable {
    @Guide(description: "Where the value is concentrated at this buffet, in one sentence")
    var claim: String

    var category: MenuCategory
    var basis: ValueBasis
    var confidence: ConfidenceBand

    @Guide(description: "The rating you expect from that category, committed before tasting")
    var expectedRating: Rating
}

@Generable
struct RoundIntent: Sendable {
    @Guide(description: "What this round is for, in one sentence")
    var rationale: String

    @Guide(description: """
        How much of this round is spent LEARNING rather than ENJOYING. \
        Learning costs capacity you cannot get back, so it is only worth it early, \
        while there is still capacity to act on what you learn. \
        none — spend everything on dishes already known to be good. \
        quarter — mostly exploit, one small taste of something unknown. \
        half — an even split. \
        most — this round is mainly reconnaissance. \
        Late in the meal, or when the winners are already known, choose none or quarter.
        """)
    var reconShare: ReconShare

    @Guide(description: "Dish names worth spending capacity to learn about. Choose ONLY from the dishes listed in the message.",
           .maximumCount(4))
    var learnAbout: [String]

    @Guide(description: """
        conservative — stick to safe, known-good choices. \
        balanced — the default. \
        aggressive — accept a poor plate for the chance of a great one.
        """)
    var riskPosture: Posture

    static let balanced = RoundIntent(rationale: PlannerObjective.balanced.rationale,
                                      reconShare: PlannerObjective.balanced.reconShare,
                                      learnAbout: [],
                                      riskPosture: PlannerObjective.balanced.posture)
}

@Generable
struct RoundDecision: Sendable {
    @Guide(description: "First, state what the tool results actually say. One sentence.")
    var because: String

    @Guide(description: """
        Now choose, consistent with what you just wrote: \
        pivot — the tools say the hypothesis is CONTRADICTED; the value is at a different category. \
        exploit — the tools say the hypothesis is SUPPORTED; spend the remaining capacity on those winners.
        """)
    var move: RoundMove
}

enum TraceKind: String, Sendable {
    case hypothesis, intent, toolCall, verdict, decision, guardrail, plan, stop, decline, modelFailure
}

/// A guard overruling the AI: what it wrote, what it chose, and what was done instead.
struct GuardOverride: Sendable, Equatable {
    let wrote: String
    let chose: RoundMove
    let forced: RoundMove
    let guardName: String
    let did: String
}

struct TraceEntry: Identifiable, Sendable {
    let id = UUID()
    let at = Date.now
    let kind: TraceKind
    let title: String
    let detail: String
    /// Calculated by the app rather than written by the AI.
    let isCalculated: Bool
    var override: GuardOverride?

    /// The row's heading in plain words; `title` keeps the name the code and model use.
    var heading: String {
        switch title {
        case "hypothesis":                    "The guess"
        case "roundIntent":                   "The goal for this round"
        case "plan":                          "The plan"
        case "plan (adjusted)":               "The plan, adjusted"
        case "plan (degraded)":               "A plan without the AI"
        case "exploit":                       "Stayed with the guess"
        case "pivot":                         "Changed course"
        case "tools":                         "What was checked"
        case "retry":                         "Asked the AI again"
        case "availability":                  "Apple Intelligence"
        case "model tier":                    "AI features on this iPhone"
        case "loop budget":                   "Out of time or attempts"
        case "context overflow":              "The AI ran out of room"
        case "hypothesise failed", "setIntent failed", "decide failed":
                                              "The AI's answer couldn't be read"
        case "Consistency guard overrode the model", "Verdict guard overrode the model":
                                              "Kenyang overruled the AI"
        case "pivot guard":                   "Kenyang changed course"
        case "adjust guard":                  "Kenyang moved the plan your way"
        case "untestable category":           "A guess that couldn't be tested"
        case "skipped to priors":             "You skipped the AI"
        case "adjust requested":              "You asked for a different plan"
        case "exclusion resolved":            "You answered an ingredient question"
        case "dish removed":                  "A dish came off the plan"
        case "re-planned":                    "Planned again"
        case "orders changed":                "You changed an order count"
        case "decline overridden":            "You asked for a plan anyway"
        case "stop overridden":               "You kept going"
        case "passed":                        "You skipped a dish"
        case "fullness":                      "You said how full you are"
        case "rateDish":                      "You rated a dish"
        case "evaluateHypothesis":            "Tested the guess"
        case "recommendStop":                 "Time to stop"
        case "declineToOptimise":             "No plan needed"
        default:                              title.prefix(1).uppercased() + title.dropFirst()
        }
    }

    /// What a guard did, in the diner's words, for the plan screen.
    var guardExplanation: String {
        let name = title.lowercased()
        if name.contains("adjust") { return "The AI didn't change the plan the way you asked, so Kenyang did." }
        if name.contains("pivot") { return "Your ratings didn't back the guess, so this round tries somewhere else." }
        return "The AI's reasoning didn't match what it chose, so Kenyang followed your ratings."
    }

    /// The AI's own sentences are worth reading at a glance; the rest is the record.
    var isWorthShowingInFull: Bool { kind == .hypothesis || kind == .intent }
}

@MainActor
@Observable
final class TraceLog {
    private(set) var entries: [TraceEntry] = []

    func record(_ kind: TraceKind, _ title: String, _ detail: String,
                calculated: Bool = true, override: GuardOverride? = nil) {
        entries.append(TraceEntry(kind: kind, title: title, detail: detail,
                                  isCalculated: calculated, override: override))
    }

    func clear() { entries.removeAll() }

    var lastGuard: TraceEntry? {
        entries.last { $0.kind == .guardrail && $0.title.localizedCaseInsensitiveContains("guard") }
    }

    var changedCourse: Bool {
        entries.contains { $0.kind == .decision && $0.title == RoundMove.pivot.rawValue }
    }
}

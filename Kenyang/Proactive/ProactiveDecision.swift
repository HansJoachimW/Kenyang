import Foundation

/// What the proactive trigger decides to do — and **why it says nothing** when it says
/// nothing.
///
/// `BUFFET.md` §10b: *"An agent that notifies on every trigger is a scheduler. One that
/// runs, concludes it has nothing earned to say — either because it has too little
/// history, or because the answer has not changed since last time — and says nothing,
/// has made a decision."*
///
/// Both silences carry a reason, because **a silence nobody can account for is
/// indistinguishable from a bug**, and the whole claim here is that the quiet branch is
/// judgement rather than a failed trigger. The trace records it either way.
enum ProactiveDecision: Equatable, Sendable {
    case notify(title: String, body: String)
    case silent(Silence)

    enum Silence: String, Sendable {
        /// One tier is not a ladder, so there is no decision to make.
        case noLadder
        /// Too little history to separate *"you like the premium cuts"* from *"you
        /// bought the premium tier twice and ate the same karubi both times"*.
        case tooFewVisits
        /// The answer is the tier you already buy. Saying so is a scheduler's behaviour.
        case unchanged

        var explanation: String {
            switch self {
            case .noLadder:     "one menu — there is no tier decision to make here"
            case .tooFewVisits: "too few visits to argue from"
            case .unchanged:    "the answer is the tier you already buy"
            }
        }
    }

    /// **Deterministic on purpose.** `TESTS.md` T58 asks whether `SystemLanguageModel`
    /// works from a `BGTask` and it **has not run**; its stated fallback is *"rules +
    /// template"*, so that is what ships until it does.
    ///
    /// The model would phrase this line, never choose it — the choice is
    /// `TierEngine.verdict`, which is the same arithmetic Screen 2 argues from. A
    /// notification that failed to fire because an unmeasured background model call hung
    /// would be worse than one that reads plainly, and the trigger only gets one shot at
    /// the moment that matters.
    static func decide(for restaurant: Restaurant) -> ProactiveDecision {
        switch TierEngine.verdict(for: restaurant) {
        case .noLadder:
            .silent(.noLadder)

        case .insufficient:
            .silent(.tooFewVisits)

        case .recommend(let tier, _, let habitual, let saving, _):
            tier == habitual
                ? .silent(.unchanged)
                : .notify(title: "Before you order at \(restaurant.name)",
                          body: body(tier: tier, habitual: habitual, saving: saving))
        }
    }

    private static func body(tier: String, habitual: String, saving: Double?) -> String {
        var line = "You usually buy \(habitual). Your own ratings say \(tier) covers what you actually finish."
        if let saving, saving > 0 {
            line += " Rp \(saving.formatted(.number.precision(.fractionLength(0)))) you would not spend."
        }
        return line
    }
}

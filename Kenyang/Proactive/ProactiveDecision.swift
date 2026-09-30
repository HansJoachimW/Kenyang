import Foundation

/// Whether to tell the diner which tier to buy before they order. Most of the time the
/// answer is to stay silent, and the silence records why.
enum ProactiveDecision: Equatable, Sendable {
    case notify(title: String, body: String)
    case silent(Silence)

    enum Silence: String, Sendable {
        case noLadder, tooFewVisits, unchanged

        var explanation: String {
            switch self {
            case .noLadder:     "one menu — there is no tier decision to make here"
            case .tooFewVisits: "too few visits to argue from"
            case .unchanged:    "the answer is the tier you already buy"
            }
        }
    }

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

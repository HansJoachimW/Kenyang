import Foundation

/// Rejects a move that contradicts the reason the AI gave for it.
enum ConsistencyGuard {
    static func agrees(reason: String, move: RoundMove) -> Bool {
        let lower = reason.lowercased()
        let saysDisproved = ["contradict", "not supported", "elsewhere", "disprove"].contains { lower.contains($0) }
        let saysHolds = ["support", "confirm", "holds"].contains { lower.contains($0) }
        switch move {
        case .pivot:   return !saysHolds || saysDisproved
        case .exploit: return !saysDisproved
        }
    }
}

/// Why the diner asked for a different plan. A closed set, so nothing the diner types
/// reaches a prompt.
enum AdjustDirection: String, CaseIterable, Sendable {
    case newThings, moreLiked, safer

    var label: String {
        switch self {
        case .newThings: "Try new things"
        case .moreLiked: "More of what I liked"
        case .safer:     "Play it safe"
        }
    }

    var promptLine: String {
        switch self {
        case .newThings: "They want to try more dishes they have not had."
        case .moreLiked: "They want more of the dishes they already rated well."
        case .safer:     "They want fewer risky choices."
        }
    }
}

/// Checks that an adjusted goal moved the way the diner asked, and steps it there if not.
enum AdjustGuard {
    static func accepts(_ new: RoundIntent, rejected: RoundIntent, direction: AdjustDirection?) -> Bool {
        let reconChange = rank(of: new.reconShare) - rank(of: rejected.reconShare)
        let postureChange = rank(of: new.riskPosture) - rank(of: rejected.riskPosture)
        switch direction {
        case .newThings: return reconChange > 0 || rejected.reconShare == .most
        case .moreLiked: return reconChange < 0 || rejected.reconShare == .none
        case .safer:     return postureChange < 0 || rejected.riskPosture == .conservative
        case nil:        return reconChange != 0 || postureChange != 0
        }
    }

    static func fallback(from rejected: RoundIntent, direction: AdjustDirection?) -> RoundIntent {
        var intent = rejected
        intent.learnAbout = []
        switch direction {
        case .newThings:
            intent.reconShare = step(rejected.reconShare, by: 1)
            intent.rationale = "Adjusted: more of this round goes to dishes you have not tried."
        case .moreLiked:
            intent.reconShare = step(rejected.reconShare, by: -1)
            intent.rationale = "Adjusted: more of this round goes to dishes you rated well."
        case .safer:
            intent.riskPosture = step(rejected.riskPosture, by: -1)
            intent.rationale = "Adjusted: safer choices this round."
        case nil:
            intent.reconShare = rank(of: rejected.reconShare) >= 2 ? .quarter : .most
            intent.rationale = "Adjusted: a different balance of learning and enjoying."
        }
        return intent
    }

    private static func rank<T: CaseIterable & Equatable>(of value: T) -> Int {
        Array(T.allCases).firstIndex(of: value) ?? 0
    }

    private static func step<T: CaseIterable & Equatable>(_ value: T, by delta: Int) -> T {
        let all = Array(T.allCases)
        return all[max(0, min(all.count - 1, rank(of: value) + delta))]
    }
}

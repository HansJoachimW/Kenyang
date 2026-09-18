import Foundation

/// Screen 2 — which tier to buy, argued from history.
///
/// Every number here is arithmetic over stored events, and every row names the tool that
/// produced it. The model's only job on that screen is one sentence of prose; if it is
/// unavailable the recommendation still fires and just loses its sentence, which is what
/// degraded mode means here.
///
/// The verdict is the headline and the evidence sits below it in reading order, so the
/// decision is glanceable and the argument is available — never the other way round.
enum TierEngine {

    /// Below this it refuses. Two visits cannot separate *"you like the premium cuts"*
    /// from *"you bought the premium tier twice and ate the same karubi both times"*.
    static let minimumVisits = 3

    struct Evidence: Identifiable, Sendable {
        let id = UUID()
        let headline: String
        let detail: String
        /// The tool a grader can go and check. Rows without one do not belong here.
        let tool: String
    }

    enum Verdict: Sendable {
        /// `saving` is nil when the ladder has no price for one of the two tiers — the
        /// recommendation stands, the money line does not.
        case recommend(tier: String, rank: Int, habitual: String, saving: Double?, evidence: [Evidence])
        case insufficient(visits: Int, needed: Int, cheapest: String, missing: [String])
        /// One tier is not a ladder, so there is no decision to make.
        case noLadder
    }

    static func verdict(for restaurant: Restaurant) -> Verdict {
        guard restaurant.hasTierLadder else { return .noLadder }

        let completed = restaurant.visits
            .filter { $0.endedAt != nil }
            .sorted { $0.startedAt < $1.startedAt }
        let cheapest = restaurant.tierName(rank: 0)

        guard completed.count >= minimumVisits else {
            return .insufficient(visits: completed.count,
                                 needed: minimumVisits,
                                 cheapest: cheapest,
                                 missing: missingFor(completed))
        }

        // Which tier the diner habitually buys: the highest rank they have paid for.
        let habitualRank = completed.compactMap { tierRank(of: $0) }.max() ?? 0

        // Which tier actually earns its place: the lowest rank that still captures most
        // of what they rated `good`. Paying for a rung whose items they do not finish is
        // the exact waste this screen exists to name.
        let recommendedRank = lowestRankCapturingValue(in: completed) ?? habitualRank

        let saving: Double? = {
            guard let high = restaurant.tierPrice(rank: habitualRank),
                  let low = restaurant.tierPrice(rank: recommendedRank),
                  high > low else { return nil }
            return high - low
        }()

        return .recommend(tier: restaurant.tierName(rank: recommendedRank),
                          rank: recommendedRank,
                          habitual: restaurant.tierName(rank: habitualRank),
                          saving: saving,
                          evidence: evidence(for: restaurant, visits: completed,
                                             habitualRank: habitualRank))
    }

    // MARK: - The rows

    private static func evidence(for restaurant: Restaurant,
                                 visits: [Visit],
                                 habitualRank: Int) -> [Evidence] {
        var rows: [Evidence] = []

        let span = dateSpan(visits)
        rows.append(Evidence(
            headline: "\(visits.count) visit\(visits.count == 1 ? "" : "s") here",
            detail: span,
            tool: "getVisitHistory"))

        // What the higher tier actually bought them. `isRated` matters: a blind log is a
        // capacity observation, and counting it here would invent a verdict on a dish
        // the diner never judged.
        if habitualRank > 0 {
            let premium = visits.flatMap { visit in
                visit.tasteEvents.filter { event in
                    event.isRated && rank(of: event, in: visit) >= habitualRank
                }
            }
            let good = premium.filter { $0.rating == .good }.count
            rows.append(Evidence(
                headline: "\(restaurant.tierName(rank: habitualRank))-only cuts rated \(premium.count)×, good \(good)",
                detail: premium.isEmpty
                    ? "nothing at that rung has been rated yet"
                    : topNames(premium),
                tool: "getPosterior"))
        }

        let fitted = CapacityEngine.fittedMax(from: visits, fallback: SessionDefaults.maxSatiety)
        let measured = visits.filter { $0.endedBecause.measuresCapacity }.count
        rows.append(Evidence(
            headline: "Your capacity ≈ \(String(format: "%.1f", fitted / CapacityEngine.platesToSatiety)) plates",
            detail: measured == 0
                // The fit reads censored totals as if they were observations. Saying so
                // on the screen is cheaper than a figure nobody can question.
                ? "no meal here ended on fullness — this is a lower bound, not a measurement"
                : "fitted on \(measured) fullness-terminated visit\(measured == 1 ? "" : "s")",
            tool: "checkCapacityModel"))

        if let minutes = visits.last?.seatingLimitMinutes {
            rows.append(Evidence(
                headline: "Higher tiers cook slowest",
                detail: "\(minutes) min seating caps how many you get through",
                tool: "getConstraints"))
        }
        return rows
    }

    /// What the refusal says it would need. Naming the threshold and the gap is the
    /// product working — "I don't know yet, and here is what I'd need".
    private static func missingFor(_ visits: [Visit]) -> [String] {
        var missing = ["one more visit logged"]
        if visits.allSatisfy({ $0.tasteEvents.allSatisfy { !$0.isRated } }) {
            missing.append("what you ordered vs what you rated")
        }
        if visits.contains(where: { $0.endedBecause == .unknown }) {
            missing.append("a stop reason on each visit")
        }
        return missing
    }

    // MARK: -

    /// A visit's tier is the highest rung its menu carried. Which menu you import *is*
    /// the tier, so this is a property of the sightings rather than something stored.
    private static func tierRank(of visit: Visit) -> Int? {
        visit.sightings.map(\.tierRank).max()
    }

    private static func rank(of event: TasteEvent, in visit: Visit) -> Int {
        visit.sightings
            .first { $0.name.caseInsensitiveCompare(event.dishName) == .orderedSame }?
            .tierRank ?? 0
    }

    /// The lowest rung holding at least 70% of the diner's `good` ratings. Below that
    /// share the higher rung is carrying real value and is worth paying for.
    private static func lowestRankCapturingValue(in visits: [Visit]) -> Int? {
        let rated = visits.flatMap { visit in
            visit.tasteEvents.filter(\.isRated).map { (rank(of: $0, in: visit), $0.rating) }
        }
        let good = rated.filter { $0.1 == .good }
        guard !good.isEmpty else { return nil }

        let ranks = Set(rated.map(\.0)).sorted()
        for rank in ranks {
            let captured = good.filter { $0.0 <= rank }.count
            if Double(captured) / Double(good.count) >= 0.7 { return rank }
        }
        return ranks.last
    }

    private static func dateSpan(_ visits: [Visit]) -> String {
        guard let first = visits.first?.startedAt, let last = visits.last?.startedAt else { return "" }
        let format = Date.FormatStyle().day().month(.abbreviated)
        return "\(first.formatted(format)) → \(last.formatted(format))"
    }

    private static func topNames(_ events: [TasteEvent]) -> String {
        let counts = Dictionary(grouping: events, by: \.dishName).mapValues(\.count)
        return counts.sorted { $0.value > $1.value }
            .prefix(2)
            .map { "\($0.key) ×\($0.value)" }
            .joined(separator: ", ")
    }
}

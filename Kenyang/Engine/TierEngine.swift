import Foundation

/// Which tier to buy, argued from the diner's own history. It only ever argues down the
/// ladder, and refuses below `minimumVisits`.
enum TierEngine {
    static let minimumVisits = 3
    static let valueShareToKeep = 0.7

    struct Evidence: Identifiable, Sendable {
        let id = UUID()
        let headline: String
        let detail: String
    }

    enum Verdict: Sendable {
        case recommend(tier: String, rank: Int, habitual: String, saving: Double?, evidence: [Evidence])
        case insufficient(visits: Int, needed: Int, cheapest: String, missing: [String])
        case noLadder
    }

    static func verdict(for restaurant: Restaurant) -> Verdict {
        guard restaurant.hasTierLadder else { return .noLadder }

        let visits = restaurant.visits.filter { !$0.isActive }.sorted { $0.startedAt < $1.startedAt }
        guard visits.count >= minimumVisits else {
            return .insufficient(visits: visits.count,
                                 needed: minimumVisits,
                                 cheapest: restaurant.tierName(rank: 0),
                                 missing: missingEvidence(in: visits))
        }

        let habitualRank = visits.compactMap(tierRank(of:)).max() ?? 0
        let recommendedRank = lowestRankKeepingMostGoodRatings(in: visits) ?? habitualRank
        var saving: Double?
        if let high = restaurant.tierPrice(rank: habitualRank),
           let low = restaurant.tierPrice(rank: recommendedRank),
           high > low {
            saving = high - low
        }

        return .recommend(tier: restaurant.tierName(rank: recommendedRank),
                          rank: recommendedRank,
                          habitual: restaurant.tierName(rank: habitualRank),
                          saving: saving,
                          evidence: evidence(for: restaurant, visits: visits, habitualRank: habitualRank))
    }

    private static func evidence(for restaurant: Restaurant, visits: [Visit], habitualRank: Int) -> [Evidence] {
        var rows = [Evidence(headline: "\(visits.count) visits here", detail: dateSpan(visits))]

        if habitualRank > 0 {
            let premium = visits.flatMap { visit in
                visit.tasteEvents.filter { $0.isRated && rank(of: $0, in: visit) >= habitualRank }
            }
            let good = premium.filter { $0.rating == .good }.count
            rows.append(Evidence(
                headline: "\(restaurant.tierName(rank: habitualRank))-only dishes rated \(premium.count)×, good \(good)",
                detail: premium.isEmpty ? "nothing on that tier rated yet" : mostOrdered(premium)))
        }

        let fitted = CapacityEngine.fittedMax(from: visits, fallback: DinerPreferences.maxSatiety)
        let plates = (fitted / CapacityEngine.platesToSatiety).formatted(.number.precision(.fractionLength(1)))
        let measured = visits.filter { $0.endedBecause.measuresCapacity }.count
        rows.append(Evidence(
            headline: "Room for about \(plates) plates",
            detail: measured == 0
                ? "no meal here ended with you full, so it may be more"
                : "from \(measured) meal\(measured == 1 ? "" : "s") that ended with you full"))

        if let minutes = visits.last?.seatingLimitMinutes {
            rows.append(Evidence(headline: "Higher tiers cook slowest",
                                 detail: "\(minutes) min seating caps how many you get through"))
        }
        return rows
    }

    private static func missingEvidence(in visits: [Visit]) -> [String] {
        var missing = ["one more visit logged"]
        if visits.allSatisfy({ $0.tasteEvents.allSatisfy { !$0.isRated } }) {
            missing.append("ratings for what you ordered")
        }
        if visits.contains(where: { $0.endedBecause == .unknown }) {
            missing.append("why each meal ended")
        }
        return missing
    }

    private static func tierRank(of visit: Visit) -> Int? {
        visit.sightings.map(\.tierRank).max()
    }

    private static func rank(of event: TasteEvent, in visit: Visit) -> Int {
        visit.sighting(named: event.dishName)?.tierRank ?? 0
    }

    private static func lowestRankKeepingMostGoodRatings(in visits: [Visit]) -> Int? {
        let rated = visits.flatMap { visit in
            visit.tasteEvents.filter(\.isRated).map { (rank: rank(of: $0, in: visit), rating: $0.rating) }
        }
        let good = rated.filter { $0.rating == .good }
        guard !good.isEmpty else { return nil }

        let ranks = Set(rated.map(\.rank)).sorted()
        let keeping = ranks.first { rank in
            Double(good.filter { $0.rank <= rank }.count) / Double(good.count) >= valueShareToKeep
        }
        return keeping ?? ranks.last
    }

    private static func dateSpan(_ visits: [Visit]) -> String {
        guard let first = visits.first?.startedAt, let last = visits.last?.startedAt else { return "" }
        let format = Date.FormatStyle().day().month(.abbreviated)
        return "\(first.formatted(format)) → \(last.formatted(format))"
    }

    private static func mostOrdered(_ events: [TasteEvent]) -> String {
        Dictionary(grouping: events, by: \.dishName)
            .map { (name: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
            .prefix(2)
            .map { "\($0.name) ×\($0.count)" }
            .joined(separator: ", ")
    }
}

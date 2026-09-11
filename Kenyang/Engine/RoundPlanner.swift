import Foundation

struct PlannedItem: Identifiable, Sendable {
    let id = UUID()
    let dishName: String
    let category: MenuCategory
    let portion: PortionBucket
    let isRecon: Bool
    let satietyCost: Double
}

struct RoundPlan: Sendable {
    var items: [PlannedItem]
    var rationale: String
    var reconShare: ReconShare
    var posture: Posture
    var totalSatietyCost: Double { items.reduce(0) { $0 + $1.satietyCost } }
    var reconCount: Int { items.filter(\.isRecon).count }
    var isEmpty: Bool { items.isEmpty }
}

struct PlannerObjective: Sendable {
    var reconShare: ReconShare
    var learnAbout: [String]
    var avoidProfile: FlavourAxis?
    var posture: Posture
    var rationale: String

    static let balanced = PlannerObjective(reconShare: .quarter,
                                           learnAbout: [],
                                           avoidProfile: nil,
                                           posture: .balanced,
                                           rationale: "Balanced default")
}

struct RoundPlanner {
    static let beamWidth = 24
    static let maxItems = 4

    static func plan(objective: PlannerObjective,
                     candidates: [DishSighting],
                     events: [TasteEvent],
                     capacity: CapacityState,
                     exclusions: [String]) -> RoundPlan {

        let allowed = candidates.filter {
            ExclusionValidator.verdict(for: $0, exclusions: exclusions) == .safe
        }
        guard !allowed.isEmpty else {
            return RoundPlan(items: [], rationale: objective.rationale,
                             reconShare: objective.reconShare, posture: objective.posture)
        }

        let budget = min(capacity.remaining, CapacityEngine.platesToSatiety * 1.2)
        guard budget > 0.2 else {
            return RoundPlan(items: [], rationale: objective.rationale,
                             reconShare: objective.reconShare, posture: objective.posture)
        }

        let learnSet = Set(objective.learnAbout.map { $0.lowercased() })

        func score(_ sighting: DishSighting, alreadyChosen: [DishSighting]) -> Double {
            let posterior = ValueEngine.posterior(dishName: sighting.name,
                                                  category: sighting.category,
                                                  events: events)
            var value = SatietyDiscount.discountedValue(for: sighting, events: events)

            let simulated = events + alreadyChosen.map {
                TasteEvent(dishName: $0.name, category: $0.category,
                           rating: .fine, portion: .normal, roundIndex: 0)
            }
            value *= SatietyDiscount.discount(for: sighting, history: simulated)

            let recon = objective.reconShare.fraction

            value += posterior.uncertainty * recon * 0.8

            let categoriesChosen = Set(alreadyChosen.map(\.category))
            let coverage = categoriesChosen.contains(sighting.category) ? -1.0 : 1.0
            value += coverage * recon * 0.9

            value += (1 - recon) * posterior.mean * 0.7

            if learnSet.contains(sighting.name.lowercased()) { value += 0.5 * (0.4 + recon) }
            if let avoid = objective.avoidProfile, sighting.flavour.axes.contains(avoid) {
                value -= 0.6
            }
            value += posterior.uncertainty * objective.posture.uncertaintyWeight * 0.4
            if sighting.isTerminal && capacity.fractionRemaining > 0.35 {
                value -= 0.7
            }
            if sighting.queueMinutes > 0 {
                value -= Double(sighting.queueMinutes) / 60.0
            }
            return value
        }

        var beam: [[DishSighting]] = [[]]

        for _ in 0..<maxItems {
            var expanded: [(path: [DishSighting], score: Double)] = []
            for path in beam {
                let used = path.reduce(0.0) { $0 + ValueEngine.satietyCost(for: $1) }
                for candidate in allowed where !path.contains(where: { $0.name == candidate.name }) {
                    let cost = ValueEngine.satietyCost(for: candidate)
                    guard used + cost <= budget else { continue }
                    let next = path + [candidate]
                    let total = next.enumerated().reduce(0.0) { acc, pair in
                        acc + score(pair.element, alreadyChosen: Array(next.prefix(pair.offset)))
                    }
                    expanded.append((next, total))
                }
            }
            guard !expanded.isEmpty else { break }
            beam = expanded.sorted { $0.score > $1.score }.prefix(beamWidth).map(\.path)
        }

        guard let best = beam.max(by: { lhs, rhs in
            let l = lhs.enumerated().reduce(0.0) { acc, pair in
                acc + score(pair.element, alreadyChosen: Array(lhs.prefix(pair.offset)))
            }
            let r = rhs.enumerated().reduce(0.0) { acc, pair in
                acc + score(pair.element, alreadyChosen: Array(rhs.prefix(pair.offset)))
            }
            return l < r
        }), !best.isEmpty else {
            return RoundPlan(items: [], rationale: objective.rationale,
                             reconShare: objective.reconShare, posture: objective.posture)
        }

        let reconTarget = Int((Double(best.count) * objective.reconShare.fraction).rounded())
        let ordered = orderForSatiety(best)

        let items = ordered.enumerated().map { index, sighting -> PlannedItem in
            let posterior = ValueEngine.posterior(dishName: sighting.name,
                                                  category: sighting.category,
                                                  events: events)
            let isRecon = index < reconTarget || posterior.sampleCount == 0
            let portion: PortionBucket = isRecon ? .taste : .normal
            return PlannedItem(dishName: sighting.name,
                               category: sighting.category,
                               portion: portion,
                               isRecon: isRecon,
                               satietyCost: portion.multiplier * sighting.category.satietyDensity)
        }

        return RoundPlan(items: items,
                         rationale: objective.rationale,
                         reconShare: objective.reconShare,
                         posture: objective.posture)
    }

    private static func orderForSatiety(_ sightings: [DishSighting]) -> [DishSighting] {
        var remaining = sightings
        var ordered: [DishSighting] = []
        while !remaining.isEmpty {
            if let last = ordered.last {
                remaining.sort { lhs, rhs in
                    lhs.flavour.similarity(to: last.flavour) < rhs.flavour.similarity(to: last.flavour)
                }
            } else {
                remaining.sort { !$0.isTerminal && $1.isTerminal }
            }
            ordered.append(remaining.removeFirst())
        }
        return ordered
    }
}

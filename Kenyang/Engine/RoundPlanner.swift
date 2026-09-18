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

    /// Dishes whose ingredients the app could not determine. A binary validator fails
    /// open and calls these *safe*; this one refuses to plan them — but refusing is
    /// only half the job. Silently dropping them is what made a single exclusion empty
    /// every plan with no explanation, so they leave the planner by name and the
    /// surfaces above ask staff about them.
    var deferToStaff: [String] = []

    /// How many dishes the exclusion list ruled out outright. Counted, not named: the
    /// list is an input and the app never explains why something is on it.
    var excludedCount: Int = 0

    var totalSatietyCost: Double { items.reduce(0) { $0 + $1.satietyCost } }
    var reconCount: Int { items.filter(\.isRecon).count }
    var isEmpty: Bool { items.isEmpty }

    /// An empty plan the diner can act on, versus one that just says nothing.
    var hasUnresolvedDishes: Bool { !deferToStaff.isEmpty }
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

        let partition = ExclusionValidator.partition(candidates, exclusions: exclusions)
        let allowed = partition.safe
        let deferToStaff = partition.unknown.map(\.name).sorted()

        func empty() -> RoundPlan {
            RoundPlan(items: [], rationale: objective.rationale,
                      reconShare: objective.reconShare, posture: objective.posture,
                      deferToStaff: deferToStaff, excludedCount: partition.excluded.count)
        }

        guard !allowed.isEmpty else { return empty() }

        let budget = min(capacity.remaining, CapacityEngine.platesToSatiety * 1.2)
        guard budget > 0.2 else { return empty() }

        let learnSet = Set(objective.learnAbout.map { $0.lowercased() })

        // Reconnaissance is a property of the dish, not of its position in the list.
        // A dish nobody has rated cannot be exploited — there is nothing to exploit —
        // and a dish the agent asked to learn about is a taste by definition. Deciding
        // it once, here, is what keeps the beam search costing the portion it will
        // actually serve: the search used to price every candidate at `.normal` and the
        // emitted plan then served 0.4× tastes, so a first round at a new venue spent
        // 40% of the budget it had been allocated.
        func isRecon(_ sighting: DishSighting) -> Bool {
            if learnSet.contains(sighting.name.lowercased()) { return true }
            return ValueEngine.posterior(dishName: sighting.name,
                                         category: sighting.category,
                                         events: events).sampleCount == 0
        }

        func portion(_ sighting: DishSighting) -> PortionBucket {
            isRecon(sighting) ? .taste : .normal
        }

        func cost(_ sighting: DishSighting) -> Double {
            ValueEngine.satietyCost(for: sighting, portion: portion(sighting))
        }

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
                let used = path.reduce(0.0) { $0 + cost($1) }
                for candidate in allowed where !path.contains(where: { $0.name == candidate.name }) {
                    guard used + cost(candidate) <= budget else { continue }
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
            return empty()
        }

        let items = orderForSatiety(best).map { sighting -> PlannedItem in
            PlannedItem(dishName: sighting.name,
                        category: sighting.category,
                        portion: portion(sighting),
                        isRecon: isRecon(sighting),
                        satietyCost: cost(sighting))
        }

        return RoundPlan(items: items,
                         rationale: objective.rationale,
                         reconShare: objective.reconShare,
                         posture: objective.posture,
                         deferToStaff: deferToStaff,
                         excludedCount: partition.excluded.count)
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

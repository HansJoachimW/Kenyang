import Foundation

struct PlannedItem: Identifiable, Sendable {
    let id = UUID()
    let dishName: String
    let category: MenuCategory
    let portion: PortionBucket
    /// Never rated, so this round orders it once to learn from.
    let isRecon: Bool
    /// Across all of its orders.
    var satietyCost: Double
    var reason: String = ""
    var quantity: Int = 1
    /// The avoid list can't settle it yet; the round waits until the diner asks staff.
    var needsCheck: Bool = false

    var orderLabel: String { quantity > 1 ? "\(dishName) ×\(quantity)" : dishName }
}

struct RoundPlan: Sendable {
    var items: [PlannedItem]
    var rationale: String
    var reconShare: ReconShare
    var posture: Posture
    var excludedCount: Int = 0

    var isEmpty: Bool { items.isEmpty }
    var totalSatietyCost: Double { items.reduce(0) { $0 + $1.satietyCost } }
    var dishesToAskAbout: [String] { items.filter(\.needsCheck).map(\.dishName) }
    var needsAnswers: Bool { !dishesToAskAbout.isEmpty }
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

/// Beam search over orders, under the objective the AI chose. A path may repeat a dish;
/// the satiety discount prices each repeat below the one before.
struct RoundPlanner {
    static let beamWidth = 24
    static let maxDishes = 4
    static let maxOrders = 6
    static let maxOrdersPerDish = 3

    let objective: PlannerObjective
    let events: [TasteEvent]
    let capacity: CapacityState
    private let learnSet: Set<String>

    static func plan(objective: PlannerObjective,
                     candidates: [DishSighting],
                     events: [TasteEvent],
                     capacity: CapacityState,
                     exclusions: [String]) -> RoundPlan {
        RoundPlanner(objective: objective, events: events, capacity: capacity)
            .plan(candidates: candidates, exclusions: exclusions)
    }

    private init(objective: PlannerObjective, events: [TasteEvent], capacity: CapacityState) {
        self.objective = objective
        self.events = events
        self.capacity = capacity
        self.learnSet = Set(objective.learnAbout.map { $0.lowercased() })
    }

    private func plan(candidates: [DishSighting], exclusions: [String]) -> RoundPlan {
        let verdicts = ExclusionValidator.partition(candidates, exclusions: exclusions)
        let allowed = verdicts.safe + verdicts.unknown
        let unchecked = Set(verdicts.unknown.map(\.name))
        let budget = min(capacity.remaining, CapacityEngine.platesToSatiety * 1.2)

        var plan = RoundPlan(items: [],
                             rationale: objective.rationale,
                             reconShare: objective.reconShare,
                             posture: objective.posture,
                             excludedCount: verdicts.excluded.count)
        guard !allowed.isEmpty, budget > 0.2 else { return plan }

        let best = bestPath(from: allowed, budget: budget)
        let dishes = best.reduce(into: [DishSighting]()) { distinct, sighting in
            if !distinct.contains(where: { $0.name == sighting.name }) { distinct.append(sighting) }
        }
        plan.items = Self.orderedByContrast(dishes).map { sighting in
            let quantity = best.filter { $0.name == sighting.name }.count
            return PlannedItem(dishName: sighting.name,
                               category: sighting.category,
                               portion: .normal,
                               isRecon: isRecon(sighting),
                               satietyCost: cost(of: sighting) * Double(quantity),
                               reason: reason(for: sighting),
                               quantity: quantity,
                               needsCheck: unchecked.contains(sighting.name))
        }
        return plan
    }

    private func bestPath(from allowed: [DishSighting], budget: Double) -> [DishSighting] {
        var beam: [(path: [DishSighting], score: Double)] = [([], 0)]
        for _ in 0..<Self.maxOrders {
            let expanded = beam.flatMap { entry in
                allowed.filter { canAdd($0, to: entry.path, budget: budget) }.map { entry.path + [$0] }
            }
            guard !expanded.isEmpty else { break }
            let scored = expanded.map { (path: $0, score: score($0)) }
            beam = Array(scored.sorted { $0.score > $1.score }.prefix(Self.beamWidth))
        }
        return beam.max { $0.score < $1.score }?.path ?? []
    }

    private func canAdd(_ sighting: DishSighting, to path: [DishSighting], budget: Double) -> Bool {
        let orders = path.filter { $0.name == sighting.name }.count
        let dishCount = Set(path.map(\.name)).count
        let used = path.reduce(0) { $0 + cost(of: $1) }
        return orders < orderLimit(for: sighting)
            && (orders > 0 || dishCount < Self.maxDishes)
            && used + cost(of: sighting) <= budget
    }

    private func score(_ path: [DishSighting]) -> Double {
        path.indices.reduce(0) { total, index in
            total + score(path[index], after: Array(path[..<index]))
        }
    }

    private func score(_ sighting: DishSighting, after chosen: [DishSighting]) -> Double {
        let posterior = ValueEngine.posterior(dishName: sighting.name, category: sighting.category, events: events)
        let recon = objective.reconShare.fraction
        let simulated = events + chosen.map {
            TasteEvent(dishName: $0.name, category: $0.category, rating: .fine, portion: .normal, roundIndex: 0)
        }

        var value = SatietyDiscount.discountedValue(for: sighting, events: events)
        value *= SatietyDiscount.discount(for: sighting, history: simulated)
        value += posterior.uncertainty * recon * 0.8
        value += (chosen.contains { $0.category == sighting.category } ? -1 : 1) * recon * 0.9
        value += (1 - recon) * posterior.mean * 0.7
        value += posterior.uncertainty * objective.posture.uncertaintyWeight * 0.4
        if learnSet.contains(sighting.name.lowercased()) { value += 0.5 * (0.4 + recon) }
        if let avoid = objective.avoidProfile, sighting.flavour.axes.contains(avoid) { value -= 0.6 }
        if sighting.isTerminal && capacity.fractionRemaining > 0.35 { value -= 0.7 }
        if sighting.queueMinutes > 0 { value -= Double(sighting.queueMinutes) / 60 }
        return value
    }

    private func isRecon(_ sighting: DishSighting) -> Bool {
        learnSet.contains(sighting.name.lowercased())
            || ValueEngine.posterior(dishName: sighting.name, category: sighting.category, events: events).sampleCount == 0
    }

    private func orderLimit(for sighting: DishSighting) -> Int {
        isRecon(sighting) ? 1 : Self.maxOrdersPerDish
    }

    private func cost(of sighting: DishSighting) -> Double {
        ValueEngine.satietyCost(for: sighting)
    }

    private func reason(for sighting: DishSighting) -> String {
        let ratings = events.filter {
            $0.isRated && $0.dishName.caseInsensitiveCompare(sighting.name) == .orderedSame
        }
        let good = ratings.filter { $0.rating == .good }.count
        let times = ratings.count == 1 ? "time" : "times"
        if ratings.isEmpty { return "Never rated here. One order to learn from." }
        if good > 0 { return "Rated good \(good) of \(ratings.count) \(times)." }
        return "Rated \(ratings.count) \(times), never good."
    }

    /// Dessert last, and each dish unlike the one before it.
    private static func orderedByContrast(_ dishes: [DishSighting]) -> [DishSighting] {
        var remaining = dishes.sorted { !$0.isTerminal && $1.isTerminal }
        var ordered: [DishSighting] = []
        while !remaining.isEmpty {
            if let last = ordered.last {
                remaining.sort { $0.flavour.similarity(to: last.flavour) < $1.flavour.similarity(to: last.flavour) }
            }
            ordered.append(remaining.removeFirst())
        }
        return ordered
    }
}

import Foundation

struct DishPosterior: Sendable {
    let dishName: String
    let category: MenuCategory
    let mean: Double
    let sampleCount: Int
    let uncertainty: Double

    var isTrustworthy: Bool { sampleCount >= ValueEngine.minimumSamples }
}

enum ValueEngine {
    static let minimumSamples = 2
    static let verdictBand = 0.25

    static func posterior(dishName: String, category: MenuCategory, events: [TasteEvent]) -> DishPosterior {
        let ratings = events
            .filter { $0.isRated && $0.dishName.caseInsensitiveCompare(dishName) == .orderedSame }
            .map(\.rating.score)
        guard !ratings.isEmpty else {
            return DishPosterior(dishName: dishName, category: category,
                                 mean: category.priorValue, sampleCount: 0, uncertainty: 1)
        }
        let n = Double(ratings.count)
        let observed = ratings.reduce(0, +) / n
        let weight = n / (n + 1)
        return DishPosterior(dishName: dishName,
                             category: category,
                             mean: weight * observed + (1 - weight) * category.priorValue,
                             sampleCount: ratings.count,
                             uncertainty: 1 / (n + 1))
    }

    static func categoryPosterior(_ category: MenuCategory, events: [TasteEvent]) -> DishPosterior {
        let ratings = events.filter { $0.isRated && $0.category == category }.map(\.rating.score)
        guard !ratings.isEmpty else {
            return DishPosterior(dishName: category.label, category: category,
                                 mean: category.priorValue, sampleCount: 0, uncertainty: 1)
        }
        let n = Double(ratings.count)
        return DishPosterior(dishName: category.label,
                             category: category,
                             mean: ratings.reduce(0, +) / n,
                             sampleCount: ratings.count,
                             uncertainty: 1 / (n + 1))
    }

    /// One-sided in the direction the guess points: expecting *good* is disproved by
    /// worse ratings, expecting *skip* by better ones.
    static func verdict(_ posterior: DishPosterior, expecting expected: Rating) -> HypothesisVerdict {
        guard posterior.isTrustworthy else { return .insufficient }
        let holds = expected == .skip
            ? posterior.mean <= expected.score + verdictBand
            : posterior.mean >= expected.score - verdictBand
        return holds ? .supported : .contradicted
    }

    static func estimatedValue(for sighting: DishSighting, events: [TasteEvent]) -> Double {
        let mean = posterior(dishName: sighting.name, category: sighting.category, events: events).mean
        let tierBonus = sighting.tierRank > 0 ? 0.25 * min(1, Double(sighting.tierRank) / 2) : 0
        return min(1.5, mean + tierBonus)
    }

    static func satietyCost(for sighting: DishSighting, portion: PortionBucket = .normal) -> Double {
        portion.multiplier * sighting.category.satietyDensity
    }

    static func valueDensity(for sighting: DishSighting, events: [TasteEvent]) -> Double {
        let cost = satietyCost(for: sighting)
        return cost > 0 ? estimatedValue(for: sighting, events: events) / cost : 0
    }
}

/// The same flavour again tastes less good: recent similar plates lower a dish's value.
enum SatietyDiscount {
    static let lambda = 0.55

    static func discount(for sighting: DishSighting, history: [TasteEvent]) -> Double {
        guard !history.isEmpty else { return 1 }
        let recent = Array(history.suffix(6).reversed())
        let penalty = recent.enumerated().reduce(0.0) { total, pair in
            let similarity = sighting.flavour.similarity(to: .prior(for: pair.element.category))
            return total + similarity / Double(pair.offset + 1)
        }
        return max(0.15, 1 - lambda * penalty / Double(recent.count))
    }

    static func discountedValue(for sighting: DishSighting, events: [TasteEvent]) -> Double {
        ValueEngine.valueDensity(for: sighting, events: events) * discount(for: sighting, history: events)
    }
}

/// A rough rupiah value of what was eaten, stated once at the stop and never during a meal.
enum BreakEven {
    static let baseRupiahPerPortion = 18_000.0
    static let priorFloor = 0.2

    static func rupiah(for category: MenuCategory) -> Double {
        baseRupiahPerPortion * (category.priorValue + priorFloor)
    }

    static func recovered(events: [TasteEvent]) -> Double {
        events.reduce(0) { $0 + rupiah(for: $1.category) * $1.portion.multiplier }
    }
}

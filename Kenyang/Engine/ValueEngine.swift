import Foundation

struct DishPosterior: Sendable {
    let dishName: String
    let category: MenuCategory
    let mean: Double
    let sampleCount: Int
    let uncertainty: Double

    var isTrustworthy: Bool { sampleCount >= ValueEngine.minimumSamples }
}

struct ValueEngine {
    static let minimumSamples = 2

    static func posterior(dishName: String,
                          category: MenuCategory,
                          events: [TasteEvent]) -> DishPosterior {
        let matching = events.filter { $0.dishName.caseInsensitiveCompare(dishName) == .orderedSame }
        let n = matching.count
        guard n > 0 else {
            return DishPosterior(dishName: dishName,
                                 category: category,
                                 mean: category.priorValue,
                                 sampleCount: 0,
                                 uncertainty: 1.0)
        }
        let mean = matching.reduce(0.0) { $0 + $1.rating.score } / Double(n)
        let prior = category.priorValue
        let weight = Double(n) / Double(n + 1)
        let blended = weight * mean + (1 - weight) * prior
        return DishPosterior(dishName: dishName,
                             category: category,
                             mean: blended,
                             sampleCount: n,
                             uncertainty: 1.0 / Double(n + 1))
    }

    static func categoryPosterior(_ category: MenuCategory,
                                 events: [TasteEvent]) -> DishPosterior {
        let matching = events.filter { $0.category == category }
        let n = matching.count
        guard n > 0 else {
            return DishPosterior(dishName: category.label,
                                 category: category,
                                 mean: category.priorValue,
                                 sampleCount: 0,
                                 uncertainty: 1.0)
        }
        let mean = matching.reduce(0.0) { $0 + $1.rating.score } / Double(n)
        return DishPosterior(dishName: category.label,
                             category: category,
                             mean: mean,
                             sampleCount: n,
                             uncertainty: 1.0 / Double(n + 1))
    }

    static func estimatedValue(for sighting: DishSighting, events: [TasteEvent]) -> Double {
        let post = posterior(dishName: sighting.name, category: sighting.category, events: events)
        var value = post.mean
        if sighting.tierRank > 0 { value += 0.25 * min(1.0, Double(sighting.tierRank) / 2.0) }
        return min(1.5, value)
    }

    static func satietyCost(for sighting: DishSighting, portion: PortionBucket = .normal) -> Double {
        portion.multiplier * sighting.category.satietyDensity
    }

    static func valueDensity(for sighting: DishSighting, events: [TasteEvent]) -> Double {
        let cost = satietyCost(for: sighting)
        guard cost > 0 else { return 0 }
        return estimatedValue(for: sighting, events: events) / cost
    }
}

struct SatietyDiscount {
    static let lambda: Double = 0.55

    static func discount(for sighting: DishSighting, history: [TasteEvent]) -> Double {
        guard !history.isEmpty else { return 1.0 }
        let recent = history.suffix(6).reversed()
        var penalty = 0.0
        for (index, event) in recent.enumerated() {
            let decay = 1.0 / Double(index + 1)
            let similarity = sighting.flavour.similarity(to: FlavourProfile.prior(for: event.category))
            penalty += decay * similarity
        }
        let normalised = penalty / Double(max(1, recent.count))
        return max(0.15, 1.0 - lambda * normalised)
    }

    static func discountedValue(for sighting: DishSighting,
                                events: [TasteEvent]) -> Double {
        ValueEngine.valueDensity(for: sighting, events: events)
            * discount(for: sighting, history: events)
    }
}

struct BreakEven {
    static func recovered(events: [TasteEvent], sightings: [DishSighting]) -> Double {
        events.reduce(0.0) { total, event in
            let category = event.category
            let unit = 18_000.0 * (category.priorValue + 0.2)
            return total + unit * event.portion.multiplier
        }
    }

    static func projection(pricePerHead: Double,
                           sightings: [DishSighting],
                           expectedSatiety: Double) -> Double {
        guard !sightings.isEmpty else { return 0 }
        let bestDensity = sightings
            .map { 18_000.0 * ($0.category.priorValue + 0.2) / ValueEngine.satietyCost(for: $0) }
            .sorted(by: >)
            .prefix(6)
        guard !bestDensity.isEmpty else { return 0 }
        let average = bestDensity.reduce(0, +) / Double(bestDensity.count)
        return average * expectedSatiety
    }
}

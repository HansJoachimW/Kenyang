import Foundation

struct DishPosterior: Sendable {
    let dishName: String
    let station: StationCategory
    let mean: Double
    let sampleCount: Int
    let uncertainty: Double

    var isTrustworthy: Bool { sampleCount >= ValueEngine.minimumSamples }
}

struct ValueEngine {
    static let minimumSamples = 2

    static func posterior(dishName: String,
                          station: StationCategory,
                          events: [TasteEvent]) -> DishPosterior {
        let matching = events.filter { $0.dishName.caseInsensitiveCompare(dishName) == .orderedSame }
        let n = matching.count
        guard n > 0 else {
            return DishPosterior(dishName: dishName,
                                 station: station,
                                 mean: station.priorValue,
                                 sampleCount: 0,
                                 uncertainty: 1.0)
        }
        let mean = matching.reduce(0.0) { $0 + $1.rating.score } / Double(n)
        let prior = station.priorValue
        let weight = Double(n) / Double(n + 1)
        let blended = weight * mean + (1 - weight) * prior
        return DishPosterior(dishName: dishName,
                             station: station,
                             mean: blended,
                             sampleCount: n,
                             uncertainty: 1.0 / Double(n + 1))
    }

    static func stationPosterior(_ station: StationCategory,
                                 events: [TasteEvent]) -> DishPosterior {
        let matching = events.filter { $0.station == station }
        let n = matching.count
        guard n > 0 else {
            return DishPosterior(dishName: station.label,
                                 station: station,
                                 mean: station.priorValue,
                                 sampleCount: 0,
                                 uncertainty: 1.0)
        }
        let mean = matching.reduce(0.0) { $0 + $1.rating.score } / Double(n)
        return DishPosterior(dishName: station.label,
                             station: station,
                             mean: mean,
                             sampleCount: n,
                             uncertainty: 1.0 / Double(n + 1))
    }

    static func estimatedValue(for sighting: DishSighting, events: [TasteEvent]) -> Double {
        let post = posterior(dishName: sighting.name, station: sighting.station, events: events)
        var value = post.mean
        if sighting.isRationed { value += 0.25 }
        if sighting.isMadeToOrder { value += 0.12 }
        return min(1.5, value)
    }

    static func satietyCost(for sighting: DishSighting, portion: PortionBucket = .normal) -> Double {
        portion.multiplier * sighting.station.satietyDensity
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
            let similarity = sighting.flavour.similarity(to: FlavourProfile.prior(for: event.station))
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
            let station = event.station
            let unit = 18_000.0 * (station.priorValue + 0.2)
            return total + unit * event.portion.multiplier
        }
    }

    static func projection(pricePerHead: Double,
                           sightings: [DishSighting],
                           expectedSatiety: Double) -> Double {
        guard !sightings.isEmpty else { return 0 }
        let bestDensity = sightings
            .map { 18_000.0 * ($0.station.priorValue + 0.2) / ValueEngine.satietyCost(for: $0) }
            .sorted(by: >)
            .prefix(6)
        guard !bestDensity.isEmpty else { return 0 }
        let average = bestDensity.reduce(0, +) / Double(bestDensity.count)
        return average * expectedSatiety
    }
}

import Foundation
import SwiftData

@Model
final class Restaurant {
    #Index<Restaurant>([\.name])
    @Attribute(.unique) var name: String
    var pricePerHead: Double
    var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \Visit.restaurant) var visits: [Visit]

    init(name: String, pricePerHead: Double = 0) {
        self.name = name
        self.pricePerHead = pricePerHead
        self.createdAt = .now
        self.visits = []
    }
}

@Model
final class Visit {
    var startedAt: Date
    var endedAt: Date?
    var seatingLimitMinutes: Int?
    var pricePerHead: Double
    var declaredMaxSatiety: Double
    var outcomeRaw: String
    var restaurant: Restaurant?

    @Relationship(deleteRule: .cascade, inverse: \DishSighting.visit) var sightings: [DishSighting]
    @Relationship(deleteRule: .cascade, inverse: \TasteEvent.visit) var tasteEvents: [TasteEvent]
    @Relationship(deleteRule: .cascade, inverse: \FullnessReading.visit) var fullnessReadings: [FullnessReading]

    init(restaurant: Restaurant?,
         pricePerHead: Double,
         seatingLimitMinutes: Int?,
         declaredMaxSatiety: Double) {
        self.startedAt = .now
        self.pricePerHead = pricePerHead
        self.seatingLimitMinutes = seatingLimitMinutes
        self.declaredMaxSatiety = declaredMaxSatiety
        self.outcomeRaw = SessionOutcome.planning.rawValue
        self.restaurant = restaurant
        self.sightings = []
        self.tasteEvents = []
        self.fullnessReadings = []
    }

    var outcome: SessionOutcome {
        get { SessionOutcome(rawValue: outcomeRaw) ?? .planning }
        set { outcomeRaw = newValue.rawValue }
    }

    var isActive: Bool { endedAt == nil }

    var elapsedMinutes: Int {
        Int(Date.now.timeIntervalSince(startedAt) / 60)
    }

    var minutesRemaining: Int? {
        guard let limit = seatingLimitMinutes else { return nil }
        return max(0, limit - elapsedMinutes)
    }
}

@Model
final class DishSighting {
    #Index<DishSighting>([\.name])
    var name: String
    var stationRaw: String
    var isRationed: Bool
    var isMadeToOrder: Bool
    var queueMinutes: Int
    var ingredientsKnown: Bool
    var ingredients: [String]
    var visit: Visit?

    init(name: String,
         station: StationCategory,
         isRationed: Bool = false,
         isMadeToOrder: Bool = false,
         queueMinutes: Int = 0,
         ingredientsKnown: Bool = false,
         ingredients: [String] = []) {
        self.name = name
        self.stationRaw = station.rawValue
        self.isRationed = isRationed
        self.isMadeToOrder = isMadeToOrder
        self.queueMinutes = queueMinutes
        self.ingredientsKnown = ingredientsKnown
        self.ingredients = ingredients
    }

    var station: StationCategory {
        get { StationCategory(rawValue: stationRaw) ?? .unknown }
        set { stationRaw = newValue.rawValue }
    }

    var flavour: FlavourProfile { .prior(for: station) }
}

@Model
final class TasteEvent {
    var at: Date
    var dishName: String
    var stationRaw: String
    var ratingRaw: String
    var portionRaw: String
    var roundIndex: Int
    var visit: Visit?

    init(dishName: String,
         station: StationCategory,
         rating: Rating,
         portion: PortionBucket,
         roundIndex: Int) {
        self.at = .now
        self.dishName = dishName
        self.stationRaw = station.rawValue
        self.ratingRaw = rating.rawValue
        self.portionRaw = portion.rawValue
        self.roundIndex = roundIndex
    }

    var station: StationCategory { StationCategory(rawValue: stationRaw) ?? .unknown }
    var rating: Rating { Rating(rawValue: ratingRaw) ?? .fine }
    var portion: PortionBucket { PortionBucket(rawValue: portionRaw) ?? .normal }

    var satietyCost: Double { portion.multiplier * station.satietyDensity }
}

@Model
final class FullnessReading {
    var at: Date
    var value: Int
    var cumulativeSatiety: Double
    var visit: Visit?

    init(value: Int, cumulativeSatiety: Double) {
        self.at = .now
        self.value = value
        self.cumulativeSatiety = cumulativeSatiety
    }
}

@Model
final class DietaryExclusion {
    @Attribute(.unique) var term: String
    var createdAt: Date

    init(term: String) {
        self.term = term.lowercased()
        self.createdAt = .now
    }
}

@Model
final class BasisRecord {
    var basisRaw: String
    var expectedScore: Double
    var actualScore: Double
    var at: Date

    init(basis: ValueBasis, expectedScore: Double, actualScore: Double) {
        self.basisRaw = basis.rawValue
        self.expectedScore = expectedScore
        self.actualScore = actualScore
        self.at = .now
    }

    var basis: ValueBasis { ValueBasis(rawValue: basisRaw) ?? .preference }
    var absoluteError: Double { abs(expectedScore - actualScore) }
}

enum KenyangSchema {
    static let models: [any PersistentModel.Type] = [
        Restaurant.self,
        Visit.self,
        DishSighting.self,
        TasteEvent.self,
        FullnessReading.self,
        DietaryExclusion.self,
        BasisRecord.self
    ]
}

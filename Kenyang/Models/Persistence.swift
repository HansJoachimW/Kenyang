import Foundation
import SwiftData

// Every stored property has a default and none is ever renamed: SwiftData reads a rename
// as drop-plus-add, and the migration failure aborts the app at launch.

@Model
final class Restaurant: Identifiable {
    #Index<Restaurant>([\.name])
    @Attribute(.unique) var name: String
    var pricePerHead: Double = 0
    var tierNames: [String] = []
    var tierPrices: [Double] = []
    var createdAt: Date = Date.now
    var latitude: Double? = nil
    var longitude: Double? = nil
    @Relationship(deleteRule: .cascade, inverse: \Visit.restaurant) var visits: [Visit]

    init(name: String, pricePerHead: Double = 0, tierNames: [String] = []) {
        self.name = name
        self.pricePerHead = pricePerHead
        self.tierNames = tierNames
        self.createdAt = .now
        self.visits = []
    }

    var id: String { name }
    var hasTierLadder: Bool { tierNames.count > 1 }

    func tierName(rank: Int) -> String {
        tierNames.indices.contains(rank) ? tierNames[rank] : "Tier \(rank + 1)"
    }

    func tierPrice(rank: Int) -> Double? {
        tierPrices.indices.contains(rank) ? tierPrices[rank] : nil
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
    var endedBecauseRaw: String = MealEnding.unknown.rawValue
    var restaurant: Restaurant?

    @Relationship(deleteRule: .cascade, inverse: \DishSighting.visit) var sightings: [DishSighting]
    @Relationship(deleteRule: .cascade, inverse: \TasteEvent.visit) var tasteEvents: [TasteEvent]
    @Relationship(deleteRule: .cascade, inverse: \FullnessReading.visit) var fullnessReadings: [FullnessReading]

    init(restaurant: Restaurant?, pricePerHead: Double, seatingLimitMinutes: Int?, declaredMaxSatiety: Double) {
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

    var endedBecause: MealEnding {
        get { MealEnding(rawValue: endedBecauseRaw) ?? .unknown }
        set { endedBecauseRaw = newValue.rawValue }
    }

    var isActive: Bool { endedAt == nil }
    var venueName: String { restaurant?.name ?? "Kenyang" }

    var minutesRemaining: Int? {
        guard let limit = seatingLimitMinutes else { return nil }
        let elapsed = Int(Date.now.timeIntervalSince(startedAt) / 60)
        return max(0, limit - elapsed)
    }

    var roundsPlayed: Int { tasteEvents.map(\.roundIndex).max() ?? 0 }

    var likedDishes: [String] {
        let liked = tasteEvents.filter { $0.isRated && $0.rating == .good }.map(\.dishName)
        return liked.reduce(into: []) { names, name in if !names.contains(name) { names.append(name) } }
    }

    func sighting(named name: String) -> DishSighting? {
        sightings.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }
}

@Model
final class DishSighting {
    #Index<DishSighting>([\.name])
    var name: String
    var categoryRaw: String = MenuCategory.unknown.rawValue
    var printedCategory: String = ""
    var tierRank: Int = 0
    var isTerminal: Bool = false
    var queueMinutes: Int = 0
    var ingredientsKnown: Bool = false
    var ingredients: [String] = []
    /// Avoid-list terms the diner cleared for this dish after asking staff. Per term, so
    /// adding a new term to the list re-opens the question.
    var clearedTerms: [String] = []
    var visit: Visit?

    init(name: String, category: MenuCategory, printedCategory: String = "", tierRank: Int = 0) {
        self.name = name
        self.categoryRaw = category.rawValue
        self.printedCategory = printedCategory
        self.tierRank = tierRank
        self.isTerminal = category == .dessert
    }

    var category: MenuCategory {
        get { MenuCategory(rawValue: categoryRaw) ?? .unknown }
        set { categoryRaw = newValue.rawValue }
    }

    var flavour: FlavourProfile { .prior(for: category) }
}

/// One plate eaten. Unrated plates count toward capacity but never toward value.
@Model
final class TasteEvent {
    var at: Date
    var dishName: String = ""
    var categoryRaw: String = MenuCategory.unknown.rawValue
    var ratingRaw: String
    var isRated: Bool = true
    var portionRaw: String
    var roundIndex: Int
    var visit: Visit?

    init(dishName: String, category: MenuCategory, rating: Rating?, portion: PortionBucket, roundIndex: Int) {
        self.at = .now
        self.dishName = dishName
        self.categoryRaw = category.rawValue
        self.isRated = rating != nil
        self.ratingRaw = (rating ?? .fine).rawValue
        self.portionRaw = portion.rawValue
        self.roundIndex = roundIndex
    }

    var category: MenuCategory { MenuCategory(rawValue: categoryRaw) ?? .unknown }
    var portion: PortionBucket { PortionBucket(rawValue: portionRaw) ?? .normal }
    var satietyCost: Double { portion.multiplier * category.satietyDensity }

    var rating: Rating {
        get { Rating(rawValue: ratingRaw) ?? .fine }
        set {
            ratingRaw = newValue.rawValue
            isRated = true
        }
    }
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

/// How one of the AI's guesses turned out, by the kind of reasoning behind it.
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

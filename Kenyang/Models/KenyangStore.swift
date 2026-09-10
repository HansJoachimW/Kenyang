import Foundation
import SwiftData

@MainActor
final class KenyangStore {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    init(container: ModelContainer) {
        self.container = container
    }

    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let schema = Schema(KenyangSchema.models)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            return try ModelContainer(for: schema, configurations: configuration)
        } catch {
            fatalError("Unable to create ModelContainer: \(error)")
        }
    }

    func activeVisit() -> Visit? {
        let descriptor = FetchDescriptor<Visit>(
            predicate: #Predicate { $0.endedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return try? context.fetch(descriptor).first
    }

    func allVisits() -> [Visit] {
        let descriptor = FetchDescriptor<Visit>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func restaurant(named name: String) -> Restaurant? {
        let descriptor = FetchDescriptor<Restaurant>(predicate: #Predicate { $0.name == name })
        return try? context.fetch(descriptor).first
    }

    func findOrCreateRestaurant(named name: String, pricePerHead: Double) -> Restaurant {
        if let existing = restaurant(named: name) {
            existing.pricePerHead = pricePerHead
            return existing
        }
        let created = Restaurant(name: name, pricePerHead: pricePerHead)
        context.insert(created)
        return created
    }

    /// Records a menu tier against a venue and returns its rank in that venue's ladder.
    /// Which menu you import *is* the tier, so rank is a venue-level fact rather than
    /// something extracted per item. New tiers append, so import the base menu first.
    func tierRank(of tierName: String, atRestaurantNamed name: String, pricePerHead: Double) -> Int {
        let restaurant = findOrCreateRestaurant(named: name, pricePerHead: pricePerHead)
        if let existing = restaurant.tierNames.firstIndex(of: tierName) { return existing }
        restaurant.tierNames.append(tierName)
        save()
        return restaurant.tierNames.count - 1
    }

    func exclusions() -> [String] {
        let descriptor = FetchDescriptor<DietaryExclusion>()
        return ((try? context.fetch(descriptor)) ?? []).map(\.term)
    }

    func addExclusion(_ term: String) {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, !exclusions().contains(trimmed) else { return }
        context.insert(DietaryExclusion(term: trimmed))
        save()
    }

    func removeExclusion(_ term: String) {
        let descriptor = FetchDescriptor<DietaryExclusion>(predicate: #Predicate { $0.term == term })
        guard let match = try? context.fetch(descriptor).first else { return }
        context.delete(match)
        save()
    }

    func basisRecords() -> [BasisRecord] {
        let descriptor = FetchDescriptor<BasisRecord>(sortBy: [SortDescriptor(\.at, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func historicalEvents(for restaurant: Restaurant?) -> [TasteEvent] {
        guard let restaurant else { return [] }
        return restaurant.visits.flatMap(\.tasteEvents)
    }

    struct VocabularyAudit: Sendable {
        var sightings = 0
        var events = 0
        var undecodable = 0
        var unknown = 0

        var total: Int { sightings + events }
        var damaged: Int { undecodable + unknown }
        var isClean: Bool { damaged == 0 }
        var unknownFraction: Double { total > 0 ? Double(unknown) / Double(total) : 0 }
    }

    func auditPersistedCategories() -> VocabularyAudit {
        var audit = VocabularyAudit()
        let sightings = (try? context.fetch(FetchDescriptor<DishSighting>())) ?? []
        let events = (try? context.fetch(FetchDescriptor<TasteEvent>())) ?? []
        audit.sightings = sightings.count
        audit.events = events.count

        let raws = sightings.map(\.categoryRaw) + events.map(\.categoryRaw)
        audit.undecodable = raws.filter { MenuCategory(rawValue: $0) == nil }.count
        audit.unknown = raws.filter { MenuCategory(rawValue: $0) == .unknown }.count
        return audit
    }

    func allDishNames() -> [String] {
        let descriptor = FetchDescriptor<DishSighting>()
        let sightings = (try? context.fetch(descriptor)) ?? []
        return Array(Set(sightings.map(\.name))).sorted()
    }

    func sightings(named name: String) -> [DishSighting] {
        let descriptor = FetchDescriptor<DishSighting>(predicate: #Predicate { $0.name == name })
        return (try? context.fetch(descriptor)) ?? []
    }

    func allSightings() -> [DishSighting] {
        (try? context.fetch(FetchDescriptor<DishSighting>())) ?? []
    }

    func allRestaurants() -> [Restaurant] {
        let descriptor = FetchDescriptor<Restaurant>(sortBy: [SortDescriptor(\.name)])
        return (try? context.fetch(descriptor)) ?? []
    }

    /// The most recent rating per dish, for entities that carry it into Spotlight
    /// and for `EntityPropertyQuery` filters like *dishes I rated good at Gyu-Kaku*.
    func ratingsByDishName() -> [String: Rating] {
        let descriptor = FetchDescriptor<TasteEvent>(sortBy: [SortDescriptor(\.at, order: .forward)])
        let events = (try? context.fetch(descriptor)) ?? []
        return events.reduce(into: [:]) { latest, event in
            latest[event.dishName] = event.rating
        }
    }

    @discardableResult
    func startVisit(restaurantName: String,
                    pricePerHead: Double,
                    seatingLimitMinutes: Int?,
                    maxSatiety: Double) -> Visit {
        let restaurant = findOrCreateRestaurant(named: restaurantName, pricePerHead: pricePerHead)
        let visit = Visit(restaurant: restaurant,
                          pricePerHead: pricePerHead,
                          seatingLimitMinutes: seatingLimitMinutes,
                          declaredMaxSatiety: maxSatiety)
        context.insert(visit)
        save()
        return visit
    }

    func addSightings(_ specs: [(name: String, category: MenuCategory, printed: String, tier: Int)],
                      to visit: Visit) {
        for spec in specs {
            let sighting = DishSighting(name: spec.name,
                                        category: spec.category,
                                        printedCategory: spec.printed,
                                        tierRank: spec.tier)
            sighting.visit = visit
            context.insert(sighting)
        }
        save()
    }

    @discardableResult
    func rate(dishName: String,
              category: MenuCategory,
              rating: Rating,
              portion: PortionBucket,
              in visit: Visit,
              roundIndex: Int) -> TasteEvent {
        let event = TasteEvent(dishName: dishName,
                               category: category,
                               rating: rating,
                               portion: portion,
                               roundIndex: roundIndex)
        event.visit = visit
        context.insert(event)
        save()
        return event
    }

    func recordFullness(_ value: Int, in visit: Visit) {
        let reading = FullnessReading(value: value,
                                      cumulativeSatiety: CapacityEngine.cumulativeSatiety(for: visit))
        reading.visit = visit
        context.insert(reading)
        save()
    }

    func recordBasisOutcome(basis: ValueBasis, expected: Rating, actual: Rating) {
        context.insert(BasisRecord(basis: basis,
                                   expectedScore: expected.score,
                                   actualScore: actual.score))
        save()
    }

    func endVisit(_ visit: Visit, outcome: SessionOutcome) {
        visit.endedAt = .now
        visit.outcome = outcome
        save()
    }

    func save() {
        try? context.save()
    }
}

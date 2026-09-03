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

    func allDishNames() -> [String] {
        let descriptor = FetchDescriptor<DishSighting>()
        let sightings = (try? context.fetch(descriptor)) ?? []
        return Array(Set(sightings.map(\.name))).sorted()
    }

    func sightings(named name: String) -> [DishSighting] {
        let descriptor = FetchDescriptor<DishSighting>(predicate: #Predicate { $0.name == name })
        return (try? context.fetch(descriptor)) ?? []
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

    func addSightings(_ specs: [(name: String, station: StationCategory, rationed: Bool, madeToOrder: Bool)],
                      to visit: Visit) {
        for spec in specs {
            let sighting = DishSighting(name: spec.name,
                                        station: spec.station,
                                        isRationed: spec.rationed,
                                        isMadeToOrder: spec.madeToOrder)
            sighting.visit = visit
            context.insert(sighting)
        }
        save()
    }

    @discardableResult
    func rate(dishName: String,
              station: StationCategory,
              rating: Rating,
              portion: PortionBucket,
              in visit: Visit,
              roundIndex: Int) -> TasteEvent {
        let event = TasteEvent(dishName: dishName,
                               station: station,
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

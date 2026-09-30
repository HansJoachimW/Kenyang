import Foundation
import Observation
import SwiftData

/// Reads and writes the SwiftData store. Everything about the meal in progress lives in
/// `MealSession`.
@MainActor
@Observable
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

    // MARK: - Visits

    func activeVisit() -> Visit? {
        fetch(FetchDescriptor<Visit>(predicate: #Predicate { $0.endedAt == nil },
                                     sortBy: [SortDescriptor(\.startedAt, order: .reverse)])).first
    }

    func allVisits() -> [Visit] {
        fetch(FetchDescriptor<Visit>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)]))
    }

    func pastVisits() -> [Visit] {
        allVisits().filter { !$0.isActive }
    }

    func startVisit(at venueName: String,
                    pricePerHead: Double,
                    seatingMinutes: Int?,
                    maxSatiety: Double,
                    dishes: [BuffetMenu.Dish]) -> Visit {
        let visit = Visit(restaurant: restaurant(named: venueName, pricePerHead: pricePerHead),
                          pricePerHead: pricePerHead,
                          seatingLimitMinutes: seatingMinutes,
                          declaredMaxSatiety: maxSatiety)
        context.insert(visit)
        for dish in dishes {
            let sighting = DishSighting(name: dish.name, category: dish.category,
                                        printedCategory: dish.section, tierRank: dish.tier)
            sighting.visit = visit
            context.insert(sighting)
        }
        save()
        return visit
    }

    func endVisit(_ visit: Visit, because ending: MealEnding) {
        visit.endedAt = .now
        visit.outcome = .stopped
        visit.endedBecause = ending
        save()
    }

    // MARK: - Restaurants and dishes

    func restaurant(named name: String) -> Restaurant? {
        fetch(FetchDescriptor<Restaurant>(predicate: #Predicate { $0.name == name })).first
    }

    func allRestaurants() -> [Restaurant] {
        fetch(FetchDescriptor<Restaurant>(sortBy: [SortDescriptor(\.name)]))
    }

    func allSightings() -> [DishSighting] {
        fetch(FetchDescriptor<DishSighting>())
    }

    func sightings(named name: String) -> [DishSighting] {
        fetch(FetchDescriptor<DishSighting>(predicate: #Predicate { $0.name == name }))
    }

    func latestRatingByDish() -> [String: Rating] {
        fetch(FetchDescriptor<TasteEvent>(sortBy: [SortDescriptor(\.at)]))
            .filter(\.isRated)
            .reduce(into: [:]) { latest, event in latest[event.dishName] = event.rating }
    }

    private func restaurant(named name: String, pricePerHead: Double) -> Restaurant {
        if let existing = restaurant(named: name) {
            existing.pricePerHead = pricePerHead
            return existing
        }
        let created = Restaurant(name: name, pricePerHead: pricePerHead)
        context.insert(created)
        return created
    }

    // MARK: - Plates

    @discardableResult
    func addPlate(of dishName: String, category: MenuCategory, rating: Rating?,
                  portion: PortionBucket = .normal, round: Int, in visit: Visit) -> TasteEvent {
        let plate = TasteEvent(dishName: dishName, category: category, rating: rating,
                               portion: portion, roundIndex: round)
        plate.visit = visit
        context.insert(plate)
        save()
        return plate
    }

    func plates(of dishName: String, round: Int, in visit: Visit) -> [TasteEvent] {
        visit.tasteEvents.filter {
            $0.roundIndex == round && $0.dishName.caseInsensitiveCompare(dishName) == .orderedSame
        }
    }

    func delete(_ plate: TasteEvent) {
        context.delete(plate)
        save()
    }

    func recordFullness(_ level: Int, in visit: Visit) {
        let reading = FullnessReading(value: level, cumulativeSatiety: CapacityEngine.totalSatiety(of: visit))
        reading.visit = visit
        context.insert(reading)
        save()
    }

    // MARK: - Avoid list

    func exclusions() -> [String] {
        fetch(FetchDescriptor<DietaryExclusion>(sortBy: [SortDescriptor(\.createdAt)])).map(\.term)
    }

    func addExclusion(_ term: String) {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, !exclusions().contains(trimmed) else { return }
        context.insert(DietaryExclusion(term: trimmed))
        save()
    }

    func removeExclusion(_ term: String) {
        guard let match = fetch(FetchDescriptor<DietaryExclusion>(predicate: #Predicate { $0.term == term })).first else { return }
        context.delete(match)
        save()
    }

    /// The diner asked staff about one ingredient in one dish.
    func recordAnswer(_ term: String, contains: Bool, for sighting: DishSighting) {
        let term = term.lowercased()
        if contains {
            if !sighting.ingredients.contains(term) { sighting.ingredients.append(term) }
        } else if !sighting.clearedTerms.contains(term) {
            sighting.clearedTerms.append(term)
        }
        save()
    }

    // MARK: - How the AI's guesses turn out

    func basisRecords() -> [BasisRecord] {
        fetch(FetchDescriptor<BasisRecord>(sortBy: [SortDescriptor(\.at, order: .reverse)]))
    }

    func recordGuessOutcome(basis: ValueBasis, expected: Rating, actual: Rating) {
        context.insert(BasisRecord(basis: basis, expectedScore: expected.score, actualScore: actual.score))
        save()
    }

    // MARK: -

    func save() {
        try? context.save()
    }

    private func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) -> [T] {
        (try? context.fetch(descriptor)) ?? []
    }
}

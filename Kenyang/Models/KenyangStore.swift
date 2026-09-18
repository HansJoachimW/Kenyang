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

    func findOrCreate(named name: String, pricePerHead: Double) -> Restaurant {
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
    func tierRank(of tierName: String, venue name: String, pricePerHead: Double) -> Int {
        let restaurant = findOrCreate(named: name, pricePerHead: pricePerHead)
        if let existing = restaurant.tierNames.firstIndex(of: tierName) {
            // A re-import is the newer price; the ladder is what it costs today.
            if restaurant.tierPrices.indices.contains(existing) {
                restaurant.tierPrices[existing] = pricePerHead
                save()
            }
            return existing
        }
        restaurant.tierNames.append(tierName)
        restaurant.tierPrices.append(pricePerHead)
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

    /// The diner asked staff and the answer was no. Recorded against the term, not as a
    /// blanket "safe", so adding an exclusion later re-opens the question.
    ///
    /// This is the only path that resolves an `unknown` dish. The alternative — asking
    /// the model whether *Nasi Goreng* contains peanuts — is the confident-and-wrong
    /// failure the scope narrowing on 2026-09-04 exists to avoid, and it would be
    /// wrong in the one direction that puts someone in hospital.
    func clearExclusion(_ term: String, for sighting: DishSighting) {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, !sighting.clearedTerms.contains(trimmed) else { return }
        sighting.clearedTerms.append(trimmed)
        save()
    }

    /// The answer was yes. The term joins the ingredient list, which makes the dish
    /// `excluded` for good.
    func flagExclusion(_ term: String, for sighting: DishSighting) {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, !sighting.ingredients.contains(trimmed) else { return }
        sighting.ingredients.append(trimmed)
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
    func ratingsByDish() -> [String: Rating] {
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
        let restaurant = findOrCreate(named: restaurantName, pricePerHead: pricePerHead)
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

    /// Record that a dish was eaten. `rating` is optional on purpose: logging *that*
    /// you ate is a capacity observation and logging *how good it was* is a value
    /// observation. They are separate loops and neither may gate the other (§3e).
    @discardableResult
    func rate(dishName: String,
              category: MenuCategory,
              rating: Rating?,
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

    /// The plan the agent last produced, so a snippet can re-render itself without
    /// paying for another round of model calls. In memory only — if the process was
    /// relaunched between taps the snippet says so rather than inventing a plan.
    var lastPlan: RoundPlan?

    /// Accepting a round is the diner agreeing to eat it. `running` was already in
    /// `SessionOutcome` and unused, so this needs no schema change — and a schema
    /// change on submission day is not a risk worth taking.
    func acceptRound(_ visit: Visit) {
        visit.outcome = .running
        save()
    }

    /// The last Action Button press, held open for its reassign window.
    ///
    /// In memory, like `lastPlan`. If the process died between the two presses the
    /// window is simply gone and the second press logs a new item rather than
    /// correcting the first — which is the safe direction: a lost correction leaves an
    /// honest log, a resurrected one would delete an event the diner never revisited.
    struct PendingLog {
        var event: TasteEvent
        var itemIndex: Int
        var at: Date
    }

    var pendingLog: PendingLog?

    /// The next thing in the round the diner has not logged yet, in **plan order**.
    /// Beam search already ranked the round, so plan order is the disambiguator — that
    /// is what lets one press resolve without a picker, an unlock or a screen.
    func nextUnloggedItem(in plan: RoundPlan, visit: Visit) -> (item: PlannedItem, index: Int)? {
        let round = currentRound(in: visit)
        let logged = Set(visit.tasteEvents
            .filter { $0.roundIndex == round }
            .map { $0.dishName.lowercased() })
        for (index, item) in plan.items.enumerated() where !logged.contains(item.dishName.lowercased()) {
            return (item, index)
        }
        return nil
    }

    func delete(_ event: TasteEvent) {
        context.delete(event)
        save()
    }

    /// Stop was tapped but no reason given yet. In memory, like `lastPlan`: it is a
    /// state of the open snippet, not of the meal. `EndMealIntent` carries a required
    /// `reason` because only a `fullness` ending measures capacity — so the snippet has
    /// to ask before it can end anything, and this is the asking.
    var stopRequested = false

    /// Rounds are not persisted, so the current one is the highest logged so far.
    /// An intent fired from Siri has no view model to ask.
    func currentRound(in visit: Visit) -> Int {
        max(1, visit.tasteEvents.map(\.roundIndex).max() ?? 1)
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

    /// `ending` is what the capacity fit reads: only a `fullness` ending is an
    /// observation of capacity, and every other ending is a lower bound on it.
    func endVisit(_ visit: Visit, outcome: SessionOutcome, ending: MealEnding = .unknown) {
        visit.endedAt = .now
        visit.outcome = outcome
        visit.endedBecause = ending
        save()
    }

    func save() {
        try? context.save()
    }
}

import AppIntents
import CoreSpotlight
import Foundation

// MARK: - Menu item

/// The type the rest of criterion 3 is built on. Defining it once pays three times:
/// Shortcuts references it, Siri resolves spoken parameters against it, and Spotlight
/// indexes it so a search for "sashimi" returns the dish rather than the app.
struct MenuItemEntity: AppEntity, IndexedEntity {
    nonisolated static var typeDisplayRepresentation: TypeDisplayRepresentation { "Menu item" }
    static var defaultQuery = MenuItemEntityQuery()

    var id: String

    @Property(title: "Name")
    var name: String

    @Property(title: "Category")
    var category: MenuCategory

    @Property(title: "Venue")
    var venueName: String

    @Property(title: "Rating")
    var rating: Rating?

    var printedSection: String

    init(id: String,
         name: String,
         category: MenuCategory,
         venueName: String,
         rating: Rating?,
         printedSection: String) {
        self.id = id
        self.printedSection = printedSection
        self.name = name
        self.category = category
        self.venueName = venueName
        self.rating = rating
    }

    var displayRepresentation: DisplayRepresentation {
        var parts = [category.label]
        if !venueName.isEmpty { parts.append(venueName) }
        if let rating { parts.append("rated \(rating.rawValue)") }
        return DisplayRepresentation(title: "\(name)", subtitle: "\(parts.joined(separator: " · "))")
    }

    /// What the Spotlight result carries. T12's bar is that the tapped result is the
    /// dish itself — so it has to arrive with its rating and venue attached, not just a name.
    var attributeSet: CSSearchableItemAttributeSet {
        let set = defaultAttributeSet
        set.title = name
        set.contentDescription = displayRepresentation.subtitle?.key
        set.keywords = [name, category.label, printedSection, venueName].filter { !$0.isEmpty }
        return set
    }

    static func from(_ sighting: DishSighting, rating: Rating?) -> MenuItemEntity {
        MenuItemEntity(id: sighting.name,
                       name: sighting.name,
                       category: sighting.category,
                       venueName: sighting.visit?.restaurant?.name ?? "",
                       rating: rating,
                       printedSection: sighting.printedCategory)
    }
}

struct MenuItemEntityQuery: EntityStringQuery, EntityPropertyQuery {
    /// A comparator becomes a predicate. There is no SwiftData query behind this —
    /// the candidate set is one visit's menu, not a database.
    typealias ComparatorMappingType = @Sendable (MenuItemEntity) -> Bool

    @Dependency private var resolved: KenyangStore
    private let injected: KenyangStore?

    init() { injected = nil }

    /// `@Dependency` resolves only inside the intent perform flow, so a query built by
    /// hand cannot reach the store. The battery injects one — otherwise T6, T12 and
    /// T69 could be written but never run, which is the failure `TESTS.md` exists to
    /// prevent.
    init(store: KenyangStore) { injected = store }

    private var store: KenyangStore { injected ?? resolved }

    static var properties = QueryProperties {
        Property(\MenuItemEntity.$name) {
            EqualToComparator { value in
                { $0.name.localizedCaseInsensitiveCompare(value) == .orderedSame }
            }
        }
        Property(\MenuItemEntity.$category) {
            EqualToComparator { value in { $0.category == value } }
        }
        Property(\MenuItemEntity.$venueName) {
            EqualToComparator { value in
                { $0.venueName.localizedCaseInsensitiveCompare(value) == .orderedSame }
            }
        }
        Property(\MenuItemEntity.$rating) {
            EqualToComparator { value in { $0.rating == value } }
        }
    }

    static var sortingOptions = SortingOptions {
        SortableBy(\MenuItemEntity.$name)
        SortableBy(\MenuItemEntity.$category)
    }

    @MainActor
    func entities(for identifiers: [String]) async throws -> [MenuItemEntity] {
        let ratings = store.ratingsByDish()
        return identifiers.flatMap { store.sightings(named: $0).prefix(1) }
            .map { MenuItemEntity.from($0, rating: ratings[$0.name]) }
    }

    /// The design's rule, and it is the whole reason Siri can resolve a mispronounced
    /// *harami*: match against the items **this meal** is working from — about a
    /// dozen — not every dish ever seen. No nearest match and no fuzzy accept; an
    /// unmatched name becomes a question, never a guess.
    @MainActor
    func entities(matching string: String) async throws -> [MenuItemEntity] {
        candidates().filter { $0.name.localizedCaseInsensitiveContains(string) }
    }

    @MainActor
    func suggestedEntities() async throws -> [MenuItemEntity] {
        Array(candidates().prefix(12))
    }

    @MainActor
    func entities(matching comparators: [ComparatorMappingType],
                  mode: ComparatorMode,
                  sortedBy: [EntityQuerySort<MenuItemEntity>],
                  limit: Int?) async throws -> [MenuItemEntity] {
        var matches = everything().filter { item in
            switch mode {
            case .and: comparators.allSatisfy { $0(item) }
            case .or:  comparators.isEmpty || comparators.contains { $0(item) }
            @unknown default: comparators.allSatisfy { $0(item) }
            }
        }
        for sort in sortedBy.reversed() {
            let ascending = sort.order == .ascending
            switch sort.by {
            case \MenuItemEntity.$category:
                matches.sort { ascending ? $0.category.label < $1.category.label
                                         : $0.category.label > $1.category.label }
            default:
                matches.sort { ascending ? $0.name < $1.name : $0.name > $1.name }
            }
        }
        if let limit { matches = Array(matches.prefix(limit)) }
        return matches
    }

    /// The closed set Siri resolves against: this visit's menu, falling back to
    /// everything known when no meal is running.
    @MainActor
    private func candidates() -> [MenuItemEntity] {
        let ratings = store.ratingsByDish()
        guard let visit = store.activeVisit(), !visit.sightings.isEmpty else { return everything() }
        return visit.sightings
            .map { MenuItemEntity.from($0, rating: ratings[$0.name]) }
            .sorted { $0.name < $1.name }
    }

    @MainActor
    private func everything() -> [MenuItemEntity] {
        let ratings = store.ratingsByDish()
        var seen: Set<String> = []
        return store.allSightings()
            .filter { seen.insert($0.name).inserted }
            .map { MenuItemEntity.from($0, rating: ratings[$0.name]) }
            .sorted { $0.name < $1.name }
    }
}

// MARK: - Venue

struct VenueEntity: AppEntity, IndexedEntity {
    nonisolated static var typeDisplayRepresentation: TypeDisplayRepresentation { "Venue" }
    static var defaultQuery = VenueEntityQuery()

    var id: String

    @Property(title: "Name")
    var name: String

    @Property(title: "Visits")
    var visitCount: Int

    var tierNames: [String]

    init(id: String, name: String, visitCount: Int, tierNames: [String]) {
        self.id = id
        self.tierNames = tierNames
        self.name = name
        self.visitCount = visitCount
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)",
                              subtitle: "\(visitCount) visit\(visitCount == 1 ? "" : "s")")
    }

    var attributeSet: CSSearchableItemAttributeSet {
        let set = defaultAttributeSet
        set.title = name
        set.contentDescription = tierNames.isEmpty
            ? "\(visitCount) visits"
            : "Tiers: \(tierNames.joined(separator: ", "))"
        set.keywords = [name] + tierNames
        return set
    }

    static func from(_ restaurant: Restaurant) -> VenueEntity {
        VenueEntity(id: restaurant.name,
                    name: restaurant.name,
                    visitCount: restaurant.visits.count,
                    tierNames: restaurant.tierNames)
    }
}

struct VenueEntityQuery: EntityStringQuery {
    @Dependency private var resolved: KenyangStore
    private let injected: KenyangStore?

    init() { injected = nil }
    init(store: KenyangStore) { injected = store }

    private var store: KenyangStore { injected ?? resolved }

    @MainActor
    func entities(for identifiers: [String]) async throws -> [VenueEntity] {
        identifiers.compactMap { store.restaurant(named: $0) }.map(VenueEntity.from)
    }

    @MainActor
    func entities(matching string: String) async throws -> [VenueEntity] {
        store.allRestaurants()
            .filter { $0.name.localizedCaseInsensitiveContains(string) }
            .map(VenueEntity.from)
    }

    @MainActor
    func suggestedEntities() async throws -> [VenueEntity] {
        store.allRestaurants().map(VenueEntity.from)
    }
}

// MARK: - Visit

struct VisitEntity: AppEntity, IndexedEntity {
    nonisolated static var typeDisplayRepresentation: TypeDisplayRepresentation { "Meal" }
    static var defaultQuery = VisitEntityQuery()

    var id: String

    @Property(title: "Venue")
    var venueName: String

    @Property(title: "Started")
    var startedAt: Date

    @Property(title: "Dishes rated")
    var ratedCount: Int

    init(id: String, venueName: String, startedAt: Date, ratedCount: Int) {
        self.id = id
        self.venueName = venueName
        self.startedAt = startedAt
        self.ratedCount = ratedCount
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(venueName), \(startedAt.formatted(date: .abbreviated, time: .shortened))",
            subtitle: "\(ratedCount) dish\(ratedCount == 1 ? "" : "es") rated"
        )
    }

    var attributeSet: CSSearchableItemAttributeSet {
        let set = defaultAttributeSet
        set.title = "\(venueName) — \(startedAt.formatted(date: .abbreviated, time: .omitted))"
        set.contentDescription = "\(ratedCount) dishes rated"
        set.startDate = startedAt
        return set
    }

    /// `Visit` carries no identifier of its own, and adding a persisted one is a
    /// migration this branch does not need — B0 is the reminder of what those cost.
    /// A start instant is unique per meal in practice.
    static func identifier(for visit: Visit) -> String {
        String(visit.startedAt.timeIntervalSince1970)
    }

    static func from(_ visit: Visit) -> VisitEntity {
        VisitEntity(id: identifier(for: visit),
                    venueName: visit.restaurant?.name ?? "Unknown venue",
                    startedAt: visit.startedAt,
                    ratedCount: visit.tasteEvents.count)
    }
}

struct VisitEntityQuery: EntityStringQuery {
    @Dependency private var resolved: KenyangStore
    private let injected: KenyangStore?

    init() { injected = nil }
    init(store: KenyangStore) { injected = store }

    private var store: KenyangStore { injected ?? resolved }

    @MainActor
    func entities(for identifiers: [String]) async throws -> [VisitEntity] {
        let wanted = Set(identifiers)
        return store.allVisits()
            .filter { wanted.contains(VisitEntity.identifier(for: $0)) }
            .map(VisitEntity.from)
    }

    @MainActor
    func entities(matching string: String) async throws -> [VisitEntity] {
        store.allVisits()
            .filter { ($0.restaurant?.name ?? "").localizedCaseInsensitiveContains(string) }
            .map(VisitEntity.from)
    }

    @MainActor
    func suggestedEntities() async throws -> [VisitEntity] {
        Array(store.allVisits().prefix(10).map(VisitEntity.from))
    }
}

// MARK: - Category

/// `MenuCategory` is already an `AppEnum`, which makes it a *parameter*. This makes it
/// a *thing* — indexable in Spotlight and referenceable in Shortcuts on its own.
struct MenuCategoryEntity: AppEntity, IndexedEntity {
    nonisolated static var typeDisplayRepresentation: TypeDisplayRepresentation { "Category" }
    static var defaultQuery = MenuCategoryEntityQuery()

    var id: String

    @Property(title: "Name")
    var name: String

    var category: MenuCategory

    init(_ category: MenuCategory) {
        self.id = category.rawValue
        self.category = category
        self.name = category.label
    }

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }

    var attributeSet: CSSearchableItemAttributeSet {
        let set = defaultAttributeSet
        set.title = name
        set.keywords = [name, category.rawValue]
        return set
    }
}

struct MenuCategoryEntityQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [MenuCategoryEntity] {
        identifiers.compactMap(MenuCategory.init(rawValue:)).map(MenuCategoryEntity.init)
    }

    func entities(matching string: String) async throws -> [MenuCategoryEntity] {
        MenuCategory.allCases
            .filter { $0.label.localizedCaseInsensitiveContains(string) }
            .map(MenuCategoryEntity.init)
    }

    func suggestedEntities() async throws -> [MenuCategoryEntity] {
        MenuCategory.allCases.map(MenuCategoryEntity.init)
    }
}

// MARK: - Enums as parameters

extension Rating: AppEnum {
    nonisolated static var typeDisplayRepresentation: TypeDisplayRepresentation { "Rating" }
    nonisolated static var caseDisplayRepresentations: [Rating: DisplayRepresentation] {
        [.skip: "Skip", .fine: "Fine", .good: "Good"]
    }
}

extension PortionBucket: AppEnum {
    nonisolated static var typeDisplayRepresentation: TypeDisplayRepresentation { "Portion" }
    nonisolated static var caseDisplayRepresentations: [PortionBucket: DisplayRepresentation] {
        [.taste: "A taste", .normal: "Normal", .lots: "Lots"]
    }
}

extension MenuCategory: AppEnum {
    nonisolated static var typeDisplayRepresentation: TypeDisplayRepresentation { "Category" }
    nonisolated static var caseDisplayRepresentations: [MenuCategory: DisplayRepresentation] {
        [.starch: "Rice & noodles", .fried: "Fried", .soup: "Soup & broth",
         .dessert: "Dessert", .meat: "Meat", .vegetable: "Vegetables",
         .raw: "Raw & sashimi", .unknown: "Unknown"]
    }
}

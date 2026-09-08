import AppIntents
import Foundation

struct DishEntity: AppEntity, IndexedEntity {
    nonisolated static var typeDisplayRepresentation: TypeDisplayRepresentation { "Dish" }
    static var defaultQuery = DishEntityQuery()

    var id: String
    var name: String
    var category: MenuCategory
    var restaurantName: String?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)",
                              subtitle: "\(category.label)\(restaurantName.map { " · \($0)" } ?? "")")
    }
}

struct DishEntityQuery: EntityStringQuery {
    @Dependency private var store: KenyangStore

    @MainActor
    func entities(for identifiers: [String]) async throws -> [DishEntity] {
        identifiers.flatMap { store.sightings(named: $0) }.map(Self.entity)
    }

    @MainActor
    func entities(matching string: String) async throws -> [DishEntity] {
        store.allDishNames()
            .filter { $0.localizedCaseInsensitiveContains(string) }
            .flatMap { store.sightings(named: $0).prefix(1) }
            .map(Self.entity)
    }

    @MainActor
    func suggestedEntities() async throws -> [DishEntity] {
        store.allDishNames().prefix(12).flatMap { store.sightings(named: $0).prefix(1) }.map(Self.entity)
    }

    static func entity(_ sighting: DishSighting) -> DishEntity {
        DishEntity(id: sighting.name,
                   name: sighting.name,
                   category: sighting.category,
                   restaurantName: sighting.visit?.restaurant?.name)
    }
}

struct RestaurantEntity: AppEntity, IndexedEntity {
    nonisolated static var typeDisplayRepresentation: TypeDisplayRepresentation { "Restaurant" }
    static var defaultQuery = RestaurantEntityQuery()

    var id: String
    var name: String
    var visitCount: Int

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(visitCount) visits")
    }
}

struct RestaurantEntityQuery: EntityStringQuery {
    @Dependency private var store: KenyangStore

    @MainActor
    func entities(for identifiers: [String]) async throws -> [RestaurantEntity] {
        identifiers.compactMap { store.restaurant(named: $0) }.map(Self.entity)
    }

    @MainActor
    func entities(matching string: String) async throws -> [RestaurantEntity] {
        store.allVisits()
            .compactMap(\.restaurant)
            .filter { $0.name.localizedCaseInsensitiveContains(string) }
            .map(Self.entity)
    }

    @MainActor
    func suggestedEntities() async throws -> [RestaurantEntity] {
        Array(Set(store.allVisits().compactMap(\.restaurant).map(\.name)))
            .compactMap { store.restaurant(named: $0) }
            .map(Self.entity)
    }

    static func entity(_ restaurant: Restaurant) -> RestaurantEntity {
        RestaurantEntity(id: restaurant.name, name: restaurant.name, visitCount: restaurant.visits.count)
    }
}

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

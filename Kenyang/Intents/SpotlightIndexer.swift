import AppIntents
import CoreSpotlight
import Foundation

/// Puts dishes, venues, meals and categories in Spotlight.
enum SpotlightIndexer {
    @MainActor
    static func reindex(_ store: KenyangStore) async {
        let ratings = store.latestRatingByDish()
        var seen: Set<String> = []
        let items = store.allSightings()
            .filter { seen.insert($0.name).inserted }
            .map { MenuItemEntity.from($0, rating: ratings[$0.name]) }
        let venues = store.allRestaurants().map(VenueEntity.from)
        let visits = store.allVisits().map(VisitEntity.from)
        let categories = MenuCategory.allCases
            .filter { $0 != .unknown }
            .map(MenuCategoryEntity.init)

        do {
            let index = CSSearchableIndex.default()
            try await index.indexAppEntities(items)
            try await index.indexAppEntities(venues)
            try await index.indexAppEntities(visits)
            try await index.indexAppEntities(categories)
        } catch {
            print("Spotlight indexing failed: \(error.localizedDescription)")
        }
    }
}

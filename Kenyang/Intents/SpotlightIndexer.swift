import AppIntents
import CoreSpotlight
import Foundation

/// T12 — put the app's entities in the system index so a search for "sashimi" returns
/// the dish, not the app.
///
/// `indexAppEntities` is the reason the four `IndexedEntity` types earn their keep:
/// the same declaration that lets Shortcuts reference a dish and Siri resolve one also
/// describes it to Spotlight, so this is a call rather than a second model.
enum SpotlightIndexer {
    @MainActor
    static func reindex(_ store: KenyangStore) async {
        let ratings = store.ratingsByDish()
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
            print("[SPOTLIGHT] indexed \(items.count) items · \(venues.count) venues · \(visits.count) meals · \(categories.count) categories")
        } catch {
            // A failed index degrades search and breaks nothing else, so it is
            // reported rather than surfaced.
            print("[SPOTLIGHT] indexing failed — \(error.localizedDescription)")
        }
    }
}

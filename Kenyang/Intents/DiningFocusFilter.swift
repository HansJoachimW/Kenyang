import AppIntents
import Foundation

/// The venue a Dining focus pins, kept in the App Group. Usually nil, so every reader
/// falls back to the default menu's venue.
enum DiningFocus {
    private static let key = "focus.venue"
    private static var defaults: UserDefaults? { UserDefaults(suiteName: MealSnapshotStore.appGroup) }

    static var venueName: String? {
        get { defaults?.string(forKey: key) }
        set { defaults?.set(newValue, forKey: key) }
    }

    static var venueForNewMeal: String {
        venueName ?? BuffetMenu.default.venueName
    }
}

/// While the focus is on, meals started from the widget or Siri begin at this venue.
struct DiningFocusFilter: SetFocusFilterIntent {
    static var title: LocalizedStringResource = "Dining at a buffet"
    static var description = IntentDescription("While this Focus is on, Kenyang assumes you are at the venue you pick here.")

    @Parameter(title: "Venue") var venue: VenueEntity?

    var displayRepresentation: DisplayRepresentation {
        guard let venue else { return DisplayRepresentation(title: "No venue pinned") }
        return DisplayRepresentation(title: "Dining at \(venue.name)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        DiningFocus.venueName = venue?.name
        return .result()
    }
}

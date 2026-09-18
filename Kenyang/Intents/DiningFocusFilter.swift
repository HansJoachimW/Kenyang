import AppIntents
import Foundation

/// Where a Dining focus's answer is kept, and the only thing that reads it.
///
/// It lives in the App Group rather than in `UserDefaults.standard` because the Control
/// Center control runs in the extension's process and needs the same answer: turn on the
/// focus, and the control's button starts the meal at the venue the focus named.
///
/// Nil is a real state and the common one — no focus, or a focus with no venue chosen —
/// so every reader must work without it. A focus filter that becomes load-bearing has
/// stopped being a filter.
enum DiningFocus {
    private static let key = "focus.venue"
    private static var defaults: UserDefaults? { UserDefaults(suiteName: MealSnapshotStore.appGroup) }

    static var venueName: String? {
        get { defaults?.string(forKey: key) }
        set {
            guard let defaults else { return }
            if let newValue { defaults.set(newValue, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
    }

    /// Where a session started from a system surface should assume it is. **This is the
    /// focus filter's entire observable consequence** — it is what makes the filter a
    /// reconfiguration rather than a setting nothing reads, and it is what the Focus
    /// filter test asserts.
    static func venueForNewSession(fallback: String = "Demo Buffet") -> String {
        venueName ?? fallback
    }
}

/// A Dining focus pins the venue.
///
/// `BUFFET.md` §10 asks for *"dining mode suppresses everything else"* — which is what
/// the system already does with the other apps, and nothing for Kenyang to implement. So
/// the reconfiguration is the one the app can actually observe: while the focus is on,
/// the app stops asking where you are.
///
/// It reconfigures **the app, not the model**. The focus says which venue; it does not
/// say how much to eat, what to order or when to stop, because those are the agent's
/// to argue and a Settings toggle that overrode them would be a way of winning that
/// argument without making it.
struct DiningFocusFilter: SetFocusFilterIntent {
    static var title: LocalizedStringResource = "Dining at a buffet"
    static var description = IntentDescription("While this Focus is on, Kenyang assumes you are at the venue you pick here.")

    @Parameter(title: "Venue")
    var venue: VenueEntity?

    var displayRepresentation: DisplayRepresentation {
        guard let venue else {
            return DisplayRepresentation(title: "No venue pinned")
        }
        return DisplayRepresentation(title: "Dining at \(venue.name)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        DiningFocus.venueName = venue?.name
        return .result()
    }
}

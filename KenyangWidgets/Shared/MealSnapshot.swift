import Foundation
import WidgetKit

/// What the home-screen widget reads.
///
/// **Why a snapshot and not the store.** A widget runs in its own process, so reading
/// SwiftData directly would mean moving the container into an App Group — which changes
/// its path, and a container that moves is a migration. `HANDOFF.md` records what the
/// last one cost: a renamed property crashed the app at launch rather than degrading.
/// The widget needs four numbers and a dish name, so it gets four numbers and a dish
/// name, written by the app whenever they change.
struct MealSnapshot: Codable, Hashable, Sendable {
    var venueName: String
    var fractionRemaining: Double
    var plateEstimate: Double
    var roundIndex: Int
    var nextTarget: String?
    var isActive: Bool
    var updatedAt: Date

    var platesText: String {
        plateEstimate < 0.75 ? "½ plate" : "\(String(format: "%.1f", plateEstimate)) plates"
    }

    static let placeholder = MealSnapshot(venueName: "Kenyang",
                                          fractionRemaining: 1,
                                          plateEstimate: 3,
                                          roundIndex: 1,
                                          nextTarget: nil,
                                          isActive: false,
                                          updatedAt: .now)
}

/// The shared container both processes read.
///
/// ⚠️ **Requires the App Group capability on both targets.** It is a signing capability,
/// so it cannot be added from here — tick *App Groups* in Signing & Capabilities for
/// **Kenyang** and **KenyangWidgets** and add `group.com.hansjoachim.Kenyang`. Until
/// then `defaults` is nil, the widget shows its placeholder, and nothing else breaks:
/// the Live Activity does not use this at all.
enum MealSnapshotStore {
    static let appGroup = "group.com.hansjoachim.Kenyang"
    private static let key = "meal.snapshot"

    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    /// True once the App Group exists. Surfaced so the battery can report the capability
    /// as missing rather than reporting the widget as broken.
    static var isConfigured: Bool { defaults != nil }

    static func write(_ snapshot: MealSnapshot) {
        guard let defaults, let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func read() -> MealSnapshot? {
        guard let defaults, let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(MealSnapshot.self, from: data)
    }

    static func clear() {
        defaults?.removeObject(forKey: key)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

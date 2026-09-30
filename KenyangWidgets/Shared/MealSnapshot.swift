import Foundation
import WidgetKit

/// What the home-screen widget and the Control Center control read. A snapshot in the
/// App Group rather than the SwiftData store, which lives in the app's own container.
struct MealSnapshot: Codable, Hashable, Sendable {
    var venueName: String
    var fractionRemaining: Double
    var plateEstimate: Double
    var round: Int
    var nextDish: String?
    var isActive: Bool
    var updatedAt: Date

    var platesText: String {
        plateEstimate < 0.75 ? "½ plate" : "\(plateEstimate.formatted(.number.precision(.fractionLength(1)))) plates"
    }

    static let placeholder = MealSnapshot(venueName: "Kenyang", fractionRemaining: 1, plateEstimate: 3,
                                          round: 1, nextDish: nil, isActive: false, updatedAt: .now)
}

/// Needs the App Group `group.com.hansjoachim.Kenyang` on both targets.
enum MealSnapshotStore {
    static let appGroup = "group.com.hansjoachim.Kenyang"
    private static let key = "meal.snapshot"
    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    static func write(_ snapshot: MealSnapshot) {
        guard let defaults, let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
        WidgetCenter.shared.reloadAllTimelines()
        ControlCenter.shared.reloadAllControls()
    }

    static func read() -> MealSnapshot? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(MealSnapshot.self, from: data)
    }
}

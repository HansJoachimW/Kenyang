import AppIntents
import SwiftUI
import WidgetKit

/// Open the app from Control Center or the Lock Screen.
///
/// Starting and ending a meal is the home-screen widget's job; this control opens the
/// app and nothing more. It reads `MealSnapshotStore` so its label names the venue while
/// a meal is running.
struct StartSessionControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "KenyangStartSession",
                                   provider: MealStateProvider()) { state in
            ControlWidgetButton(action: OpenKenyangIntent()) {
                Label(state.label, systemImage: state.isActive ? "circle.dotted" : "fork.knife")
            }
        }
        .displayName("Open Kenyang")
        .description("Open the app, or return to the meal in progress.")
    }
}

struct MealStateProvider: ControlValueProvider {
    struct Value {
        var isActive: Bool
        var label: String
    }

    let previewValue = Value(isActive: false, label: "Kenyang")

    func currentValue() async throws -> Value {
        guard let snapshot = MealSnapshotStore.read(), snapshot.isActive else {
            return Value(isActive: false, label: "Kenyang")
        }
        return Value(isActive: true, label: snapshot.venueName)
    }
}

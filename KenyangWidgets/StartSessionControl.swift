import AppIntents
import SwiftUI
import WidgetKit

/// Start a meal from Control Center or the Lock Screen.
///
/// `BUFFET.md` §10 makes this the arrival gesture: *Control Center: start session → Live
/// Activity begins*. The demo script leans on it — you sit down and there is no capture
/// step, because the menu is already stored.
///
/// The control reads `MealSnapshotStore` so it can say whether a meal is already running
/// rather than offering "Start a meal" during one. That read is why the App Group had to
/// land first: without it `MealSnapshotStore.read()` is nil and the control falls back to
/// its idle label, which is wrong but not broken.
struct StartSessionControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "KenyangStartSession",
                                   provider: MealStateProvider()) { state in
            ControlWidgetButton(action: StartSessionControlIntent()) {
                Label(state.label, systemImage: state.isActive ? "circle.dotted" : "fork.knife")
            }
        }
        .displayName("Start a meal")
        .description("Begin a buffet session and start the Live Activity.")
    }
}

struct MealStateProvider: ControlValueProvider {
    struct Value {
        var isActive: Bool
        var label: String
    }

    let previewValue = Value(isActive: false, label: "Start a meal")

    func currentValue() async throws -> Value {
        guard let snapshot = MealSnapshotStore.read(), snapshot.isActive else {
            return Value(isActive: false, label: "Start a meal")
        }
        return Value(isActive: true, label: snapshot.venueName)
    }
}

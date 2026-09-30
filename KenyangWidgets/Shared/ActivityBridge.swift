import AppIntents
import Foundation

/// The commands a Live Activity button or a Control Center control can send.
enum ActivityCommand: String, Sendable {
    case rateGood, rateSkip, stop, startSession
}

/// How a button in the widget extension reaches the app's store.
///
/// A `LiveActivityIntent`'s `perform()` runs in the **app's** process, not the
/// extension's — the extension only needs the intent *type* so it can build the button.
/// So the extension compiles this file and never uses the handler; the app compiles it
/// and registers one at launch. That is what keeps `KenyangStore` and the whole model
/// layer out of the extension target.
@MainActor
final class ActivityBridge {
    static let shared = ActivityBridge()

    private var handler: ((ActivityCommand) -> Void)?

    private init() {}

    func register(_ handler: @escaping (ActivityCommand) -> Void) {
        self.handler = handler
    }

    func send(_ command: ActivityCommand) {
        handler?(command)
    }
}

// `isDiscoverable = false` on all three: these exist to back a button on a surface that
// already names them. Listing them in Shortcuts as well would offer the diner "Rate it
// good" with no dish attached, which is the blind-rating failure the Action Button
// design rules out by name.

struct RateTargetGoodIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Rate the current dish good"
    static var isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        ActivityBridge.shared.send(.rateGood)
        return .result()
    }
}

struct RateTargetSkipIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Rate the current dish skip"
    static var isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        ActivityBridge.shared.send(.rateSkip)
        return .result()
    }
}

struct StopFromActivityIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "End the meal"
    static var isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        ActivityBridge.shared.send(.stop)
        return .result()
    }
}

/// What the home-screen widget's Start runs, from the default menu. **Not**
/// `StartSessionIntent`, which opens the app: *"an intent that only opens the app is a
/// launcher"*. The widget's End is `StopFromActivityIntent`, the Live Activity's Stop.
///
/// It is a `LiveActivityIntent` for the same reason the three above are: `perform()` has
/// to reach `KenyangStore`, which lives in the app's process and not the extension's.
/// That conformance is also literally true here: starting a session is what starts the
/// Live Activity.
///
/// Discoverable, unlike the three above, because *"start a meal"* is a complete
/// instruction on its own and belongs in Shortcuts.
struct StartMealFromWidgetIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Start a meal"
    static var description = IntentDescription("Begin a meal and start the Live Activity, without opening the app.")

    @MainActor
    func perform() async throws -> some IntentResult {
        ActivityBridge.shared.send(.startSession)
        return .result()
    }
}

/// What the Control Center control runs: it opens the app and does nothing else.
/// Starting and ending a meal belong to the home-screen widget.
struct OpenKenyangIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Kenyang"
    static var openAppWhenRun = true
    // Backs the control. Shortcuts can already open an app.
    static var isDiscoverable = false

    func perform() async throws -> some IntentResult {
        .result()
    }
}

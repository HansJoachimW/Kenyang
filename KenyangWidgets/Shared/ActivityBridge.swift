import AppIntents
import Foundation

/// The commands a Live Activity button can send.
enum ActivityCommand: String, Sendable {
    case rateGood, rateSkip, stop
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

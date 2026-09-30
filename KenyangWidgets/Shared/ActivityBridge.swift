import AppIntents
import Foundation

/// What a button on the Live Activity or the home-screen widget asks the app to do.
enum MealAction: String, AppEnum {
    case startMeal, endMeal, good, skip, nextRound, orderRound, anotherRound

    nonisolated static var typeDisplayRepresentation: TypeDisplayRepresentation { "Meal action" }
    nonisolated static var caseDisplayRepresentations: [MealAction: DisplayRepresentation] {
        [.startMeal: "Start meal", .endMeal: "End meal", .good: "Good", .skip: "Skip",
         .nextRound: "Next round", .orderRound: "Order these", .anotherRound: "Another"]
    }

    var label: String {
        Self.caseDisplayRepresentations[self].map { String(localized: $0.title) } ?? rawValue
    }
}

enum MealCommand: Sendable, Equatable {
    case perform(MealAction)
    case answer(dish: String, ingredient: String, contains: Bool)
}

/// Carries a button press from the widget extension to the app. A `LiveActivityIntent`
/// runs in the app's process, so the app registers the handler at launch and the
/// extension never needs the model layer. Async, so the system keeps the app alive while
/// a round is planned.
@MainActor
final class ActivityBridge {
    static let shared = ActivityBridge()

    private var handler: ((MealCommand) async -> Void)?

    private init() {}

    func register(_ handler: @escaping (MealCommand) async -> Void) {
        self.handler = handler
    }

    func send(_ command: MealCommand) async {
        await handler?(command)
    }
}

struct MealButtonIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Meal button"
    static var isDiscoverable = false

    @Parameter(title: "Action") var action: MealAction

    init() {}

    init(_ action: MealAction) {
        self.action = action
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        await ActivityBridge.shared.send(.perform(action))
        return .result()
    }
}

/// The diner asked staff about a planned dish and answers on the Live Activity. The
/// question goes to the diner, never to the AI.
struct IngredientAnswerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Answer an ingredient question"
    static var isDiscoverable = false

    @Parameter(title: "Dish") var dish: String
    @Parameter(title: "Ingredient") var ingredient: String
    @Parameter(title: "Contains it") var contains: Bool

    init() {}

    init(dish: String, ingredient: String, contains: Bool) {
        self.dish = dish
        self.ingredient = ingredient
        self.contains = contains
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        await ActivityBridge.shared.send(.answer(dish: dish, ingredient: ingredient, contains: contains))
        return .result()
    }
}

struct OpenKenyangIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Kenyang"
    static var openAppWhenRun = true
    static var isDiscoverable = false

    func perform() async throws -> some IntentResult {
        .result()
    }
}

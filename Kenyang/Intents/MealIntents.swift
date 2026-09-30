import AppIntents
import Foundation

// Every table-side intent answers with the app closed: the phone is face-down and the
// dialog is the whole reply.

struct StartSessionIntent: AppIntent {
    static var title: LocalizedStringResource = "Start a buffet session"
    static var description = IntentDescription("Begin a meal and start planning rounds.")
    static var openAppWhenRun = true

    @Dependency private var session: MealSession

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard session.visit == nil else { return .result(dialog: "A meal is already in progress.") }
        let visit = session.start(at: DiningFocus.venueForNewMeal)
        return .result(dialog: "Session started at \(visit.venueName).")
    }
}

struct RateDishIntent: AppIntent {
    static var title: LocalizedStringResource = "Rate a dish"
    static var description = IntentDescription("Log what you thought of a dish without opening the app.")
    static var openAppWhenRun = false

    /// Left unresolved so the system asks which dish rather than the app guessing.
    @Parameter(title: "Dish") var dish: MenuItemEntity
    @Parameter(title: "Rating") var rating: Rating
    @Parameter(title: "Portion", default: .normal) var portion: PortionBucket

    @Dependency private var session: MealSession

    static var parameterSummary: some ParameterSummary {
        Summary("Rate \(\.$dish) as \(\.$rating)") { \.$portion }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let visit = session.visit else { return .result(dialog: "No meal in progress. Start a session first.") }
        session.logDish(named: dish.name, category: dish.category, rating: rating, portion: portion)
        return .result(dialog: IntentDialog(stringLiteral: StopGuard.stopMessage(for: visit) ?? "Logged \(dish.name) as \(rating.rawValue)."))
    }
}

struct LogEatenIntent: AppIntent {
    static var title: LocalizedStringResource = "Log something I ate"
    static var description = IntentDescription("Record a dish without opening the app. Rating it is optional.")
    static var openAppWhenRun = false

    @Parameter(title: "Dish") var item: MenuItemEntity
    @Parameter(title: "How was it?") var rating: Rating?
    @Parameter(title: "Portion", default: .normal) var portion: PortionBucket

    @Dependency private var session: MealSession

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$item)") {
            \.$rating
            \.$portion
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let visit = session.visit else { return .result(dialog: "No meal in progress. Start a session first.") }
        session.logDish(named: item.name, category: item.category, rating: rating, portion: portion)
        let reply = StopGuard.stopMessage(for: visit)
            ?? "Logged \(item.name). \(CapacityEngine.state(for: visit).platesLeftSentence)"
        return .result(dialog: IntentDialog(stringLiteral: reply))
    }
}

struct SetFullnessIntent: AppIntent {
    static var title: LocalizedStringResource = "Say how full I am"
    static var description = IntentDescription("Give the agent one coarse reading of how full you are.")
    static var openAppWhenRun = false

    @Parameter(title: "How full?") var fullness: Fullness

    @Dependency private var session: MealSession

    static var parameterSummary: some ParameterSummary {
        Summary("I am \(\.$fullness)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let visit = session.visit else { return .result(dialog: "No meal in progress.") }
        session.recordFullness(fullness)
        let predicted = CapacityEngine.predictedFullness(CapacityEngine.state(for: visit))
        let comparison = switch fullness.level - predicted {
        case 2...:    "That is fuller than I expected, so I will plan smaller rounds."
        case ...(-2): "That is emptier than I expected. I had been too cautious."
        default:      "That matches what I expected."
        }
        return .result(dialog: IntentDialog(stringLiteral: "Noted. \(comparison)"))
    }
}

struct RecommendStopIntent: AppIntent {
    static var title: LocalizedStringResource = "Should I stop?"
    static var description = IntentDescription("Ask whether the meal should end now.")
    static var openAppWhenRun = false

    @Dependency private var session: MealSession

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let visit = session.visit else { return .result(dialog: "No meal in progress.") }
        let reply = StopGuard.stopMessage(for: visit)
            ?? "Not yet. \(CapacityEngine.state(for: visit).platesLeftSentence)"
        return .result(dialog: IntentDialog(stringLiteral: reply))
    }
}

struct EndMealIntent: AppIntent {
    static var title: LocalizedStringResource = "End the meal"
    static var description = IntentDescription("Finish the meal and record why it ended.")
    static var openAppWhenRun = false

    /// Only a "full" ending measures capacity, so the reason is always asked for.
    @Parameter(title: "Why are you stopping?") var reason: MealEnding

    @Dependency private var session: MealSession

    init() {}

    init(reason: MealEnding) {
        self.reason = reason
    }

    static var parameterSummary: some ParameterSummary {
        Summary("End the meal because \(\.$reason)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let visit = session.visit else { return .result(dialog: "No meal in progress.") }
        let plates = visit.tasteEvents.count
        session.end(because: reason)
        RoundSnippetIntent.reload()
        let closing = reason.measuresCapacity ? "Now I know how much you can eat." : "I'll take that as you could have eaten more."
        return .result(dialog: IntentDialog(stringLiteral: "Meal ended after \(plates) plate\(plates == 1 ? "" : "s"). \(closing)"))
    }
}

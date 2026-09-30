import AppIntents
import SwiftUI

struct PlanRoundIntent: AppIntent {
    static var title: LocalizedStringResource = "Plan the next round"
    static var description = IntentDescription("Ask the agent what to eat next.")
    static var openAppWhenRun = false

    @Dependency private var coordinator: RoundCoordinator

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let session = coordinator.session
        guard session.visit != nil else {
            return .result(dialog: "No meal in progress.", view: MealOverSnippet(headline: "Nothing to plan"))
        }
        let outcome = await coordinator.planRound(advancing: session.isEating)
        guard let plan = session.plan, let visit = session.visit else {
            return .result(dialog: IntentDialog(stringLiteral: session.note ?? "Nothing to plan."),
                           view: MealOverSnippet(headline: "Nothing to plan"))
        }
        let spoken = if case .planned(_, let hypothesis, _) = outcome { hypothesis.claim } else { session.note ?? plan.rationale }
        return .result(dialog: IntentDialog(stringLiteral: spoken),
                       view: PlanSnippet(plan: plan, capacity: CapacityEngine.state(for: visit)))
    }
}

/// The snippet redraws in place: its buttons change the meal and call `reload()`, and
/// the system runs this again. It never opens the app.
struct RoundSnippetIntent: SnippetIntent {
    static var title: LocalizedStringResource = "Show the round"

    @Dependency private var session: MealSession

    @MainActor
    func perform() async throws -> some IntentResult & ShowsSnippetView {
        guard let visit = session.store.allVisits().first else {
            return .result(view: MealOverSnippet(headline: "No meal in progress", detail: "Start a session to plan a round."))
        }
        let capacity = CapacityEngine.state(for: visit)
        if !visit.isActive {
            return .result(view: MealOverSnippet(headline: "Meal ended", detail: "\(visit.tasteEvents.count) plates logged."))
        }
        if session.isAskingWhyStopping {
            return .result(view: StopReasonSnippet())
        }
        if session.isEating {
            return .result(view: ReceiptSnippet(plan: session.plan, capacity: capacity))
        }
        guard let plan = session.plan, !plan.isEmpty else {
            return .result(view: MealOverSnippet(headline: "No plan yet", detail: "Ask for a round first."))
        }
        return .result(view: PlanSnippet(plan: plan, capacity: capacity))
    }
}

struct AcceptRoundIntent: AppIntent {
    static var title: LocalizedStringResource = "Accept the round"
    static var openAppWhenRun = false
    static var isDiscoverable = false

    @Dependency private var session: MealSession

    @MainActor
    func perform() async throws -> some IntentResult {
        session.acceptPlan()
        RoundSnippetIntent.reload()
        return .result()
    }
}

struct AdjustRoundIntent: AppIntent {
    static var title: LocalizedStringResource = "Adjust the round"
    static var openAppWhenRun = false
    static var isDiscoverable = false

    @Dependency private var coordinator: RoundCoordinator

    @MainActor
    func perform() async throws -> some IntentResult {
        await coordinator.adjustRound(toward: nil)
        RoundSnippetIntent.reload()
        return .result()
    }
}

/// Stop is two taps in the snippet: this asks why, and `EndMealIntent` ends the meal.
struct RequestStopIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop the meal"
    static var openAppWhenRun = false
    static var isDiscoverable = false

    @Dependency private var session: MealSession

    @MainActor
    func perform() async throws -> some IntentResult {
        session.isAskingWhyStopping = session.visit != nil
        RoundSnippetIntent.reload()
        return .result()
    }
}

struct ResumeRoundIntent: AppIntent {
    static var title: LocalizedStringResource = "Keep eating"
    static var openAppWhenRun = false
    static var isDiscoverable = false

    @Dependency private var session: MealSession

    @MainActor
    func perform() async throws -> some IntentResult {
        session.isAskingWhyStopping = false
        RoundSnippetIntent.reload()
        return .result()
    }
}

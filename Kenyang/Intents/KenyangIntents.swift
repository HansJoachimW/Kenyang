import AppIntents
import Foundation
import SwiftUI

struct RateDishIntent: AppIntent {
    static var title: LocalizedStringResource = "Rate a dish"
    static var description = IntentDescription("Log what you thought of a dish without opening the app.")
    static var openAppWhenRun = false

    @Parameter(title: "Dish")
    var dish: MenuItemEntity

    @Parameter(title: "Rating")
    var rating: Rating

    @Parameter(title: "Portion", default: .normal)
    var portion: PortionBucket

    @Dependency private var store: KenyangStore

    static var parameterSummary: some ParameterSummary {
        Summary("Rate \(\.$dish) as \(\.$rating)") {
            \.$portion
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let visit = store.activeVisit() else {
            return .result(dialog: "No meal in progress. Start a session first.")
        }
        store.rate(dishName: dish.name,
                   category: dish.category,
                   rating: rating,
                   portion: portion,
                   in: visit,
                   roundIndex: 1)
        let capacity = CapacityEngine.state(for: visit)
        if StopGuard.shouldStop(capacity: capacity, minutesRemaining: visit.minutesRemaining) {
            let reason = StopGuard.reason(capacity: capacity, minutesRemaining: visit.minutesRemaining)
            return .result(dialog: IntentDialog(stringLiteral: StopGuard.message(for: reason)))
        }
        return .result(dialog: "Logged \(dish.name) as \(rating.rawValue).")
    }
}

struct StartSessionIntent: AppIntent {
    static var title: LocalizedStringResource = "Start a buffet session"
    static var description = IntentDescription("Begin a meal and start planning rounds.")
    static var openAppWhenRun = true

    @Parameter(title: "Restaurant", default: "Demo Buffet")
    var restaurantName: String

    // AppIntents requires a compile-time literal here, so these two cannot read
    // SessionDefaults. Keep them in step with it by hand.
    @Parameter(title: "Price per head", default: 250_000)
    var pricePerHead: Double

    @Parameter(title: "Seating limit in minutes", default: 90)
    var seatingLimit: Int

    @Dependency private var store: KenyangStore

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        if store.activeVisit() != nil {
            return .result(dialog: "A meal is already in progress.")
        }
        let visit = store.startVisit(restaurantName: restaurantName,
                                     pricePerHead: pricePerHead,
                                     seatingLimitMinutes: seatingLimit,
                                     maxSatiety: SessionDefaults.maxSatiety)
        store.addSightings(DemoSpread.standard, to: visit)
        return .result(dialog: "Session started at \(restaurantName).")
    }
}

struct PlanRoundIntent: AppIntent {
    static var title: LocalizedStringResource = "Plan the next round"
    static var description = IntentDescription("Ask the agent what to eat next.")
    static var openAppWhenRun = false

    @Dependency private var store: KenyangStore

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        guard let visit = store.activeVisit() else {
            return .result(dialog: "No meal in progress.", view: EmptyPlanSnippet())
        }
        let trace = TraceLog()
        let agent = RoundAgent(trace: trace)
        let input = AgentInput(sightings: visit.sightings,
                               events: visit.tasteEvents,
                               capacity: CapacityEngine.state(for: visit),
                               minutesRemaining: visit.minutesRemaining,
                               exclusions: store.exclusions(),
                               basisRecords: store.basisRecords(),
                               roundIndex: visit.tasteEvents.map(\.roundIndex).max() ?? 1,
                               currentHypothesis: nil)

        switch await agent.run(input) {
        case .declined(let message):
            return .result(dialog: IntentDialog(stringLiteral: message), view: EmptyPlanSnippet())
        case .stopped(_, let message):
            return .result(dialog: IntentDialog(stringLiteral: message), view: EmptyPlanSnippet())
        case .degraded(let plan, let message):
            return .result(dialog: IntentDialog(stringLiteral: message), view: PlanSnippet(plan: plan))
        case .planned(let plan, let hypothesis, _):
            return .result(dialog: IntentDialog(stringLiteral: hypothesis.claim),
                           view: PlanSnippet(plan: plan))
        }
    }
}

struct RecommendStopIntent: AppIntent {
    static var title: LocalizedStringResource = "Should I stop?"
    static var description = IntentDescription("Ask whether the meal should end now.")
    static var openAppWhenRun = false

    @Dependency private var store: KenyangStore

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let visit = store.activeVisit() else {
            return .result(dialog: "No meal in progress.")
        }
        let capacity = CapacityEngine.state(for: visit)
        let reason = StopGuard.reason(capacity: capacity, minutesRemaining: visit.minutesRemaining)
        guard reason != .none else {
            return .result(dialog: "Not yet — about \(String(format: "%.1f", capacity.plateEstimate)) plates left.")
        }
        return .result(dialog: IntentDialog(stringLiteral: StopGuard.message(for: reason)))
    }
}

// MARK: - The table-side loop
//
// All three run with `openAppWhenRun = false`. That is the point: the phone is
// face-down on the table with tongs in your hand, and an intent that opens the app is
// a launcher, not an intent. Each one answers in its dialog, because with no screen
// involved the dialog *is* the agent's output.

struct LogEatenIntent: AppIntent {
    static var title: LocalizedStringResource = "Log something I ate"
    static var description = IntentDescription("Record a dish without opening the app. Rating it is optional.")
    static var openAppWhenRun = false

    // Left unresolved on purpose so the *system* asks which dish, rather than the app
    // guessing from a near match.
    @Parameter(title: "Dish")
    var item: MenuItemEntity

    @Parameter(title: "How was it?")
    var rating: Rating?

    @Parameter(title: "Portion", default: .normal)
    var portion: PortionBucket

    @Dependency private var store: KenyangStore

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$item)") {
            \.$rating
            \.$portion
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let visit = store.activeVisit() else {
            return .result(dialog: "No meal in progress. Start a session first.")
        }
        store.rate(dishName: item.name,
                   category: item.category,
                   rating: rating,
                   portion: portion,
                   in: visit,
                   roundIndex: store.currentRound(in: visit))

        // Every log runs the deterministic stop check (§3f).
        let capacity = CapacityEngine.state(for: visit)
        if StopGuard.shouldStop(capacity: capacity, minutesRemaining: visit.minutesRemaining) {
            let reason = StopGuard.reason(capacity: capacity, minutesRemaining: visit.minutesRemaining)
            return .result(dialog: IntentDialog(stringLiteral: StopGuard.message(for: reason)))
        }
        return .result(dialog: IntentDialog(stringLiteral: "Logged \(item.name). \(platesLeft(capacity))"))
    }

    private func platesLeft(_ capacity: CapacityState) -> String {
        let plates = capacity.plateEstimate
        if plates < 0.75 { return "About half a plate left." }
        return "About \(String(format: "%.1f", plates)) plates left."
    }
}

struct SetFullnessIntent: AppIntent {
    static var title: LocalizedStringResource = "Say how full I am"
    static var description = IntentDescription("Give the agent one coarse reading of how full you are.")
    static var openAppWhenRun = false

    @Parameter(title: "How full?")
    var fullness: Fullness

    @Dependency private var store: KenyangStore

    static var parameterSummary: some ParameterSummary {
        Summary("I am \(\.$fullness)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let visit = store.activeVisit() else {
            return .result(dialog: "No meal in progress.")
        }
        store.recordFullness(fullness.level, in: visit)

        // The reading is the diner's; the prediction is the app's. Saying which way they
        // disagree is the app falsifying itself out loud — the second calibration axis.
        let capacity = CapacityEngine.state(for: visit)
        let predicted = CapacityEngine.predictedFullness(capacity)
        let note: String
        switch fullness.level - predicted {
        case 2...:    note = "That is fuller than I expected — I will plan smaller rounds."
        case ...(-2): note = "That is emptier than I expected — I had been too cautious."
        default:      note = "That matches what I expected."
        }
        return .result(dialog: IntentDialog(stringLiteral: "Noted. \(note)"))
    }
}

struct EndMealIntent: AppIntent {
    static var title: LocalizedStringResource = "End the meal"
    static var description = IntentDescription("Finish the meal and record why it ended.")
    static var openAppWhenRun = false

    // Not cosmetic. Only a `fullness` ending measures capacity; every other ending is a
    // lower bound, and averaging the two biases the fit downward for ever (§3e).
    @Parameter(title: "Why are you stopping?")
    var reason: MealEnding

    @Dependency private var store: KenyangStore

    static var parameterSummary: some ParameterSummary {
        Summary("End the meal because \(\.$reason)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let visit = store.activeVisit() else {
            return .result(dialog: "No meal in progress.")
        }
        let eaten = visit.tasteEvents.count
        store.endVisit(visit, outcome: .stopped, ending: reason)
        let tail = reason.measuresCapacity
            ? "That gives me a real reading on your capacity."
            : "I will treat that as at least this much, not a full measurement."
        return .result(dialog: IntentDialog(stringLiteral: "Meal ended after \(eaten) item\(eaten == 1 ? "" : "s"). \(tail)"))
    }
}

struct PlanSnippet: View {
    let plan: RoundPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(plan.rationale).font(.footnote).foregroundStyle(.secondary)
            ForEach(plan.items) { item in
                HStack {
                    Text(item.dishName).font(.subheadline)
                    Spacer()
                    Text(item.isRecon ? "recon" : "exploit").font(.caption2).foregroundStyle(.secondary)
                }
            }
            HStack {
                Button(intent: PlanRoundIntent()) { Text("Adjust") }
                Button(intent: RecommendStopIntent()) { Text("Stop") }
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
}

struct EmptyPlanSnippet: View {
    var body: some View {
        Text("Nothing to plan.").font(.footnote).foregroundStyle(.secondary).padding()
    }
}

struct KenyangShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: RateDishIntent(),
                    phrases: ["Rate a dish in \(.applicationName)",
                              "Log a dish in \(.applicationName)"],
                    shortTitle: "Rate a dish",
                    systemImageName: "star")
        AppShortcut(intent: PlanRoundIntent(),
                    phrases: ["What should I eat next in \(.applicationName)",
                              "Plan a round in \(.applicationName)"],
                    shortTitle: "Plan a round",
                    systemImageName: "fork.knife")
        AppShortcut(intent: RecommendStopIntent(),
                    phrases: ["Should I stop in \(.applicationName)",
                              "Am I done in \(.applicationName)"],
                    shortTitle: "Should I stop",
                    systemImageName: "hand.raised")
        AppShortcut(intent: LogEatenIntent(),
                    phrases: ["Log a dish in \(.applicationName)",
                              "I ate something in \(.applicationName)",
                              "Log what I ate in \(.applicationName)"],
                    shortTitle: "Log a dish",
                    systemImageName: "fork.knife.circle")
        AppShortcut(intent: SetFullnessIntent(),
                    phrases: ["Set my fullness in \(.applicationName)",
                              "Say how full I am in \(.applicationName)"],
                    shortTitle: "How full I am",
                    systemImageName: "gauge.medium")
        AppShortcut(intent: EndMealIntent(),
                    phrases: ["End the meal in \(.applicationName)",
                              "I am done in \(.applicationName)"],
                    shortTitle: "End the meal",
                    systemImageName: "flag.checkered")
        AppShortcut(intent: StartSessionIntent(),
                    phrases: ["Start a buffet in \(.applicationName)",
                              "Start a session in \(.applicationName)"],
                    shortTitle: "Start a session",
                    systemImageName: "play")
    }
}

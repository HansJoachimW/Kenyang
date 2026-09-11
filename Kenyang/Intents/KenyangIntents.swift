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
        AppShortcut(intent: StartSessionIntent(),
                    phrases: ["Start a buffet in \(.applicationName)",
                              "Start a session in \(.applicationName)"],
                    shortTitle: "Start a session",
                    systemImageName: "play")
    }
}

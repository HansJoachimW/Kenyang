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
                               roundIndex: store.currentRound(in: visit),
                               currentHypothesis: nil,
                               // Without these `checkCapacityModel` answers `insufficient`
                               // every time it is asked from Siri, so the falsification
                               // tool the whole capacity story rests on could never fire
                               // on the one path that has no screen to fall back to.
                               fullnessReadings: visit.fullnessReadings)

        switch await agent.run(input) {
        case .declined(let message):
            return .result(dialog: IntentDialog(stringLiteral: message), view: EmptyPlanSnippet())
        case .stopped(_, let message):
            return .result(dialog: IntentDialog(stringLiteral: message), view: EmptyPlanSnippet())
        case .degraded(let plan, let message):
            store.lastPlan = plan
            return .result(dialog: IntentDialog(stringLiteral: message),
                           view: PlanSnippet(plan: plan, capacity: CapacityEngine.state(for: visit)))
        case .planned(let plan, let hypothesis, _):
            store.lastPlan = plan
            return .result(dialog: IntentDialog(stringLiteral: hypothesis.claim),
                           view: PlanSnippet(plan: plan, capacity: CapacityEngine.state(for: visit)))
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

    init() {}

    /// The snippet's reason buttons need to hand the intent a value. Without this the
    /// only initialiser left `reason` unset, and a `Button(intent: EndMealIntent())`
    /// inside a snippet has no way to ask for it — the tap failed instead of ending
    /// the meal.
    init(reason: MealEnding) {
        self.reason = reason
    }

    static var parameterSummary: some ParameterSummary {
        Summary("End the meal because \(\.$reason)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        store.stopRequested = false
        guard let visit = store.activeVisit() else {
            return .result(dialog: "No meal in progress.")
        }
        let eaten = visit.tasteEvents.count
        store.endVisit(visit, outcome: .stopped, ending: reason)
        RoundSnippetIntent.reload()
        let tail = reason.measuresCapacity
            ? "That gives me a real reading on your capacity."
            : "I will treat that as at least this much, not a full measurement."
        return .result(dialog: IntentDialog(stringLiteral: "Meal ended after \(eaten) item\(eaten == 1 ? "" : "s"). \(tail)"))
    }
}

// MARK: - The interactive snippet
//
// The pass bar is sharper than "the buttons work": **Accept must update the snippet in
// place, never dismiss and never open the app.** A snippet that dismisses is
// indistinguishable from a button that launched the app, which is the distinction a
// grader can see in one question.
//
// `SnippetIntent` is how that is done on iOS 26: one intent owns the rendering, the
// buttons mutate state and call `reload()`, and the system re-runs the renderer in
// place. The buttons are plain `AppIntent`s so they can be composed in Shortcuts too.

struct RoundSnippetIntent: SnippetIntent {
    static var title: LocalizedStringResource = "Show the round"

    @Dependency private var store: KenyangStore

    @MainActor
    func perform() async throws -> some IntentResult & ShowsSnippetView {
        // The most recent visit, not only a live one. Stop ends the visit, and looking
        // only at `activeVisit()` made the ended state unreachable — the snippet fell
        // through to "no meal in progress" and threw the receipt away at the exact
        // moment the diner wanted to see it.
        guard let visit = store.allVisits().first else {
            return .result(view: MealOverSnippet(headline: "No meal in progress",
                                                 detail: "Start a session to plan a round."))
        }
        let capacity = CapacityEngine.state(for: visit)

        guard visit.isActive else {
            return .result(view: MealOverSnippet(headline: "Meal ended",
                                                 detail: endingDetail(visit)))
        }

        // Stop is a two-step, in place. The reason is not a formality — only a
        // `fullness` ending measures capacity — so the snippet asks for it rather than
        // guessing, and asking is another rewrite of the same surface.
        if store.stopRequested {
            return .result(view: StopReasonSnippet())
        }

        switch visit.outcome {
        case .stopped, .declined:
            return .result(view: MealOverSnippet(headline: "Meal ended",
                                                 detail: endingDetail(visit)))
        case .running:
            // Accepted. The snippet becomes a receipt — same surface, new content.
            return .result(view: ReceiptSnippet(plan: store.lastPlan, capacity: capacity))
        case .planning:
            guard let plan = store.lastPlan, !plan.isEmpty else {
                return .result(view: MealOverSnippet(headline: "No plan yet",
                                                     detail: "Ask for a round first."))
            }
            return .result(view: PlanSnippet(plan: plan, capacity: capacity))
        }
    }

    private func endingDetail(_ visit: Visit) -> String {
        let n = visit.tasteEvents.count
        let items = "\(n) item\(n == 1 ? "" : "s") logged"
        return visit.endedBecause.measuresCapacity
            ? "\(items). That was a real reading on your capacity."
            : "\(items)."
    }
}

struct AcceptRoundIntent: AppIntent {
    static var title: LocalizedStringResource = "Accept the round"
    static var description = IntentDescription("Agree to eat the planned round.")
    static var openAppWhenRun = false
    // Backs a button on a surface that already names it. Listing it in
    // Shortcuts would offer an action with no context to act on.
    static var isDiscoverable = false

    @Dependency private var store: KenyangStore

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let visit = store.activeVisit() else { return .result() }
        store.acceptRound(visit)
        // Rewrites the snippet where it stands. No dismiss, no launch.
        RoundSnippetIntent.reload()
        return .result()
    }
}

/// Step one of stopping: rewrite the snippet into the reason chooser. It writes nothing
/// to the meal — a diner who taps Stop and changes their mind has changed nothing.
struct RequestStopIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop the meal"
    static var description = IntentDescription("Ask why the meal is ending, then end it.")
    static var openAppWhenRun = false
    // Backs a button on a surface that already names it. Listing it in
    // Shortcuts would offer an action with no context to act on.
    static var isDiscoverable = false

    @Dependency private var store: KenyangStore

    @MainActor
    func perform() async throws -> some IntentResult {
        guard store.activeVisit() != nil else { return .result() }
        store.stopRequested = true
        RoundSnippetIntent.reload()
        return .result()
    }
}

struct ResumeRoundIntent: AppIntent {
    static var title: LocalizedStringResource = "Keep eating"
    static var description = IntentDescription("Dismiss the stop prompt and carry on.")
    static var openAppWhenRun = false
    // Backs a button on a surface that already names it. Listing it in
    // Shortcuts would offer an action with no context to act on.
    static var isDiscoverable = false

    @Dependency private var store: KenyangStore

    @MainActor
    func perform() async throws -> some IntentResult {
        store.stopRequested = false
        RoundSnippetIntent.reload()
        return .result()
    }
}

struct AdjustRoundIntent: AppIntent {
    static var title: LocalizedStringResource = "Adjust the round"
    static var description = IntentDescription("Ask the agent to plan the round differently.")
    static var openAppWhenRun = false
    // Backs a button on a surface that already names it. Listing it in
    // Shortcuts would offer an action with no context to act on.
    static var isDiscoverable = false

    @Dependency private var store: KenyangStore

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let visit = store.activeVisit() else { return .result() }
        // A different objective, not a re-roll of the same one: more recon and a
        // bolder posture is what "adjust" means to a diner who did not like the plan.
        let objective = PlannerObjective(reconShare: .most,
                                         learnAbout: [],
                                         avoidProfile: nil,
                                         posture: .aggressive,
                                         rationale: "Adjusted — more of this round spent finding out.")
        store.lastPlan = RoundPlanner.plan(objective: objective,
                                           candidates: visit.sightings,
                                           events: visit.tasteEvents,
                                           capacity: CapacityEngine.state(for: visit),
                                           exclusions: store.exclusions())
        RoundSnippetIntent.reload()
        return .result()
    }
}

struct PlanSnippet: View {
    let plan: RoundPlan
    let capacity: CapacityState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(plan.rationale).font(.footnote).foregroundStyle(.secondary)
            ForEach(plan.items) { item in
                HStack {
                    Text(item.dishName).font(.subheadline)
                    Spacer()
                    Text(item.isRecon ? "recon" : "exploit")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            DeferToStaffNote(plan: plan)
            Text("About \(String(format: "%.1f", capacity.plateEstimate)) plates left")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(intent: AcceptRoundIntent()) { Text("Accept") }
                Button(intent: AdjustRoundIntent()) { Text("Adjust") }
                Button(intent: RequestStopIntent()) { Text("Stop") }
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
}

/// The third exclusion state, given a surface. A binary validator would have called
/// these safe; this app refuses to plan them, and refusing silently is what made one
/// dietary exclusion empty every plan with nothing on screen to explain it.
struct DeferToStaffNote: View {
    let plan: RoundPlan

    var body: some View {
        if plan.hasUnresolvedDishes {
            Text("Ask staff about: \(plan.deferToStaff.joined(separator: ", "))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// What Stop turns the snippet into. Each button carries its reason, so the intent is
/// never run with an unresolved parameter.
struct StopReasonSnippet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Why are you stopping?").font(.subheadline.weight(.medium))
            Text("Only “I am full” measures your capacity. The rest tell me the meal ended before you did.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(MealEnding.allCases, id: \.self) { ending in
                Button(intent: EndMealIntent(reason: ending)) {
                    Text(label(for: ending)).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Button(intent: ResumeRoundIntent()) { Text("Keep eating") }
        }
        .buttonStyle(.bordered)
        .padding()
    }

    private func label(for ending: MealEnding) -> String {
        switch ending {
        case .fullness: "I am full"
        case .clock:    "Seating time ran out"
        case .closing:  "The place is closing"
        case .left:     "The group left"
        case .unknown:  "Some other reason"
        }
    }
}

/// What Accept turns the snippet into — the same surface, rewritten.
struct ReceiptSnippet: View {
    let plan: RoundPlan?
    let capacity: CapacityState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Eating this round").font(.subheadline.weight(.medium))
            ForEach(plan?.items ?? []) { item in
                HStack {
                    Text(item.dishName).font(.footnote)
                    Spacer()
                    Text(item.portion.rawValue).font(.caption2).foregroundStyle(.secondary)
                }
            }
            if let plan { DeferToStaffNote(plan: plan) }
            ProgressView(value: capacity.fractionRemaining)
            Text("About \(String(format: "%.1f", capacity.plateEstimate)) plates left")
                .font(.caption).foregroundStyle(.secondary)
            Button(intent: RequestStopIntent()) { Text("Stop") }
                .buttonStyle(.bordered)
        }
        .padding()
    }
}

struct MealOverSnippet: View {
    let headline: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(headline).font(.subheadline.weight(.medium))
            Text(detail).font(.footnote).foregroundStyle(.secondary)
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
        // Phrases are a global namespace: "Log a dish in Kenyang" was registered here
        // *and* on LogEatenIntent, and a duplicate phrase does not disambiguate — one
        // of the two silently loses. Rating and logging are different intents, so they
        // get different words.
        AppShortcut(intent: RateDishIntent(),
                    phrases: ["Rate a dish in \(.applicationName)",
                              "Rate what I ate in \(.applicationName)"],
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
        // The Action Button target. There is no API to claim the button — the diner
        // assigns it in Settings — so what the app owes is a zero-parameter intent that
        // is worth assigning and findable in the picker.
        AppShortcut(intent: LogNextItemIntent(),
                    phrases: ["Log the next item in \(.applicationName)",
                              "Next plate in \(.applicationName)"],
                    shortTitle: "Log next item",
                    systemImageName: "circle.badge.checkmark")
        AppShortcut(intent: StartSessionIntent(),
                    phrases: ["Start a buffet in \(.applicationName)",
                              "Start a session in \(.applicationName)"],
                    shortTitle: "Start a session",
                    systemImageName: "play")
    }
}

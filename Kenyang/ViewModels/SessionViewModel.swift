import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class SessionViewModel {
    enum Phase: Equatable {
        case idle
        case planning
        case awaitingApproval
        case eating
        case stopped(String)
        case declined(String)
    }

    private let store: KenyangStore
    let trace: TraceLog
    private let agent: RoundAgent
    let progress = AgentProgress()
    private var planningTask: Task<Void, Never>?

    var phase: Phase = .idle
    var visit: Visit?
    var plan: RoundPlan?
    var hypothesis: ValueHypothesis?
    var intent: RoundIntent?
    var degradedMessage: String?
    var roundIndex = 1
    var askBudget = AskBudget()
    var pathSignatures: [String] = []

    init(store: KenyangStore, trace: TraceLog? = nil) {
        let log = trace ?? TraceLog()
        self.store = store
        self.trace = log
        self.agent = RoundAgent(trace: log, progress: progress)
        self.visit = store.activeVisit()
        if visit != nil { phase = .eating }
    }

    var capacity: CapacityState {
        guard let visit else { return CapacityState(maxSatiety: SessionDefaults.maxSatiety, spent: 0) }
        return CapacityEngine.state(for: visit)
    }

    var minutesRemaining: Int? { visit?.minutesRemaining }

    var unknownDishes: [DishSighting] {
        guard let visit else { return [] }
        return ExclusionValidator.partition(visit.sightings, exclusions: store.exclusions()).unknown
    }

    var excludedCount: Int {
        guard let visit else { return 0 }
        return ExclusionValidator.partition(visit.sightings, exclusions: store.exclusions()).excluded.count
    }

    /// What is still open, dish by dish and term by term. Driving the UI off this
    /// rather than off `unknownDishes` means a dish disappears from the list the moment
    /// its last question is answered.
    func openQuestions(for sighting: DishSighting) -> [String] {
        ExclusionValidator.unresolvedTerms(for: sighting, exclusions: store.exclusions())
    }

    /// The diner asked staff and came back with an answer. Re-planning afterwards is
    /// the point: a dish cleared mid-round should become plannable in that round, not
    /// the next one.
    func answer(_ term: String, contains: Bool, for sighting: DishSighting) {
        if contains {
            store.flagExclusion(term, for: sighting)
        } else {
            store.clearExclusion(term, for: sighting)
        }
        trace.record(kind: .guardrail,
                     title: "exclusion resolved",
                     detail: "\(sighting.name) · \(term) → \(contains ? "contains it" : "cleared by the diner")",
                     deterministic: true)
        beginPlanning()
    }

    func startSession(restaurantName: String,
                      pricePerHead: Double,
                      seatingLimit: Int?,
                      plates: Double,
                      spread: [(name: String, category: MenuCategory, printed: String, tier: Int)]) {
        let visit = store.startVisit(restaurantName: restaurantName,
                                     pricePerHead: pricePerHead,
                                     seatingLimitMinutes: seatingLimit,
                                     maxSatiety: plates * CapacityEngine.platesToSatiety)
        store.addSightings(spread, to: visit)
        self.visit = visit
        self.roundIndex = 1
        trace.clear()
        // Starting a session is the only thing that adds dishes — from a captured
        // menu or from the demo spread — so it is the one moment the Spotlight index
        // goes stale. Hooking it to menu capture alone left a demo session unindexed
        // until the next launch.
        Task { await SpotlightIndexer.reindex(store) }
        beginPlanning()
    }

    /// The escape the design puts on every stage. Thirty seconds is longer than the
    /// three-second budget allows, so the diner has to be able to leave at any point and
    /// still get a plan — the same one degraded mode produces.
    private func beginPlanning() {
        planningTask?.cancel()
        planningTask = Task { [weak self] in await self?.planRound() }
    }

    func skipToPriors() {
        guard let visit, phase == .planning else { return }
        planningTask?.cancel()
        planningTask = nil
        trace.record(kind: .guardrail,
                     title: "skipped to priors",
                     detail: "The diner left the wait. Planning from population priors instead of a composed hypothesis.",
                     deterministic: true)
        hypothesis = nil
        intent = nil
        plan = RoundPlanner.plan(objective: .balanced,
                                 candidates: visit.sightings,
                                 events: visit.tasteEvents,
                                 capacity: CapacityEngine.state(for: visit),
                                 exclusions: store.exclusions())
        degradedMessage = "Planned from priors — you skipped the agent."
        phase = .awaitingApproval
    }

    func planRound() async {
        guard let visit else { return }
        phase = .planning
        degradedMessage = nil
        progress.reset()

        // The tools publish as they return, so the wait screen shows what was actually
        // asked rather than a list of what might be.
        await ToolContext.shared.observe { [progress] name, result in
            Task { @MainActor in progress.note(tool: name, result: result) }
        }
        defer { Task { await ToolContext.shared.observe(nil) } }

        let input = AgentInput(sightings: visit.sightings,
                               events: visit.tasteEvents,
                               capacity: CapacityEngine.state(for: visit),
                               minutesRemaining: visit.minutesRemaining,
                               exclusions: store.exclusions(),
                               basisRecords: store.basisRecords(),
                               roundIndex: roundIndex,
                               currentHypothesis: hypothesis)

        let outcome = await agent.run(input)
        guard !Task.isCancelled, phase == .planning else { return }

        switch outcome {
        case .declined(let message):
            store.endVisit(visit, outcome: .declined)
            pathSignatures.append(trace.pathSignature)
            phase = .declined(message)
        case .stopped(_, let message):
            store.endVisit(visit, outcome: .stopped)
            pathSignatures.append(trace.pathSignature)
            phase = .stopped(message)
        case .degraded(let plan, let message):
            self.plan = plan
            self.degradedMessage = message
            phase = .awaitingApproval
        case .planned(let plan, let hypothesis, let intent):
            self.plan = plan
            self.hypothesis = hypothesis
            self.intent = intent
            phase = .awaitingApproval
        }
    }

    func acceptPlan() {
        phase = .eating
        syncActivity()
    }

    /// The Live Activity mirrors the meal; it never drives it. Every caller that
    /// changes capacity, phase or the plan ends here, so the Island cannot drift out of
    /// step with the app by having been forgotten at one call site.
    func syncActivity() {
        guard let visit else { return }
        let capacity = CapacityEngine.state(for: visit)
        let activityPhase = LiveActivityController.phase(
            capacity: capacity,
            minutesRemaining: visit.minutesRemaining,
            isDegraded: degradedMessage != nil,
            isEating: phase == .eating
        )
        let message: String? = {
            if activityPhase == .stopGuard {
                return StopGuard.message(for: StopGuard.reason(capacity: capacity,
                                                               minutesRemaining: visit.minutesRemaining))
            }
            return degradedMessage
        }()
        let state = LiveActivityController.state(
            phase: activityPhase,
            capacity: capacity,
            minutesRemaining: visit.minutesRemaining,
            roundIndex: roundIndex,
            nextTarget: plan.flatMap { store.nextUnloggedItem(in: $0, visit: visit)?.item.dishName },
            message: message
        )
        if LiveActivityController.shared.isRunning {
            LiveActivityController.shared.update(state)
        } else {
            LiveActivityController.shared.start(venue: visit.restaurant?.name ?? "Buffet", state: state)
        }
        LiveActivityController.shared.publishSnapshot(visit: visit, state: state)
    }

    func rate(_ item: PlannedItem, rating: Rating) {
        guard let visit else { return }
        if let hypothesis, item.category == hypothesis.category {
            store.recordBasisOutcome(basis: hypothesis.basis,
                                     expected: hypothesis.expectedRating,
                                     actual: rating)
        }
        store.rate(dishName: item.dishName,
                   category: item.category,
                   rating: rating,
                   portion: item.portion,
                   in: visit,
                   roundIndex: roundIndex)
        trace.record(kind: .toolCall,
                     title: "rateDish",
                     detail: "\(item.dishName) → \(rating.rawValue)",
                     deterministic: true)
        syncActivity()
    }

    func rate(dishNamed name: String, rating: Rating, portion: PortionBucket = .normal) {
        guard let visit else { return }
        let category = visit.sightings.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.category ?? .unknown
        store.rate(dishName: name,
                   category: category,
                   rating: rating,
                   portion: portion,
                   in: visit,
                   roundIndex: roundIndex)
        trace.record(kind: .toolCall,
                     title: "rateDish",
                     detail: "\(name) → \(rating.rawValue)",
                     deterministic: true)
    }

    func recordFullness(_ value: Int) {
        guard let visit, askBudget.hasBudget else { return }
        askBudget.spend()
        store.recordFullness(value, in: visit)
        trace.record(kind: .toolCall,
                     title: "fullness",
                     detail: "reported \(value)/5 — ask budget \(askBudget.remaining) left",
                     deterministic: true)
        syncActivity()
    }

    func nextRound() {
        roundIndex += 1
        beginPlanning()
    }

    func endSession() {
        guard let visit else { return }
        let capacity = CapacityEngine.state(for: visit)
        LiveActivityController.shared.end(
            LiveActivityController.state(phase: .stopGuard,
                                         capacity: capacity,
                                         minutesRemaining: visit.minutesRemaining,
                                         roundIndex: roundIndex,
                                         nextTarget: nil,
                                         message: "Meal ended.")
        )
        store.endVisit(visit, outcome: .stopped)
        pathSignatures.append(trace.pathSignature)
        self.visit = nil
        self.plan = nil
        self.hypothesis = nil
        phase = .idle
    }
}

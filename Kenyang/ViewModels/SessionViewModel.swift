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
        self.agent = RoundAgent(trace: log)
        self.visit = store.activeVisit()
        if visit != nil { phase = .eating }
    }

    var capacity: CapacityState {
        guard let visit else { return CapacityState(maxSatiety: 9, spent: 0) }
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
        Task { await planRound() }
    }

    func planRound() async {
        guard let visit else { return }
        phase = .planning
        degradedMessage = nil

        let input = AgentInput(sightings: visit.sightings,
                               events: visit.tasteEvents,
                               capacity: CapacityEngine.state(for: visit),
                               minutesRemaining: visit.minutesRemaining,
                               exclusions: store.exclusions(),
                               basisRecords: store.basisRecords(),
                               roundIndex: roundIndex,
                               currentHypothesis: hypothesis)

        switch await agent.run(input) {
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
    }

    func nextRound() async {
        roundIndex += 1
        await planRound()
    }

    func endSession() {
        guard let visit else { return }
        store.endVisit(visit, outcome: .stopped)
        pathSignatures.append(trace.pathSignature)
        self.visit = nil
        self.plan = nil
        self.hypothesis = nil
        phase = .idle
    }
}

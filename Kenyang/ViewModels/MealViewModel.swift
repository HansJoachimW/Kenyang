import Foundation
import Observation

/// Which screen the meal is on, and the diner's actions on it.
@MainActor
@Observable
final class MealViewModel {
    enum Screen: Equatable {
        case home, planning, plan, eating
        case stop(StopReason)
        case declined(String)
    }

    let session: MealSession
    let coordinator: RoundCoordinator
    private(set) var screen: Screen = .home
    var isShowingTrace = false

    init(session: MealSession, coordinator: RoundCoordinator) {
        self.session = session
        self.coordinator = coordinator
        syncWithSession()
    }

    /// The Live Activity, the widget and Siri change the meal while the app is away, so
    /// the screen follows the session whenever the app comes back.
    func syncWithSession() {
        if isOnGuardScreen && session.visit != nil { return }
        if session.visit == nil {
            screen = .home
        } else if coordinator.isPlanning {
            screen = .planning
        } else if session.isEating {
            screen = .eating
        } else if session.plan != nil {
            screen = .plan
        } else {
            Task { await planRound(advancing: false) }
        }
    }

    func startMeal(at venueName: String = BuffetMenu.default.venueName,
                   pricePerHead: Double = BuffetMenu.default.pricePerHead) async {
        session.start(at: venueName, pricePerHead: pricePerHead)
        await planRound(advancing: false)
    }

    func planNextRound() async {
        await planRound(advancing: true)
    }

    func planAnyway() async {
        session.trace.record(.guardrail, "decline overridden", "Triage declined and the diner asked for a plan anyway.")
        await planRound(advancing: false)
    }

    func skipTheAI() {
        coordinator.planWithoutAgent()
        screen = .plan
    }

    func adjust(toward direction: AdjustDirection) async {
        screen = .planning
        await coordinator.adjustRound(toward: direction)
        screen = .plan
    }

    func acceptPlan() {
        if session.acceptPlan() { screen = .eating }
    }

    func logAsIGo() {
        screen = .eating
    }

    func askToStop() {
        screen = .stop(.none)
    }

    func keepGoing() {
        session.trace.record(.guardrail, "stop overridden", "The guard fired and the diner chose to continue.")
        screen = .eating
    }

    func endMeal(because ending: MealEnding) {
        session.end(because: ending)
        screen = .home
    }

    private var isOnGuardScreen: Bool {
        switch screen {
        case .stop, .declined: true
        default: false
        }
    }

    private func planRound(advancing: Bool) async {
        screen = .planning
        guard let outcome = await coordinator.planRound(advancing: advancing) else { return }
        switch outcome {
        case .stopped(let reason, _): screen = .stop(reason)
        case .declined(let message):  screen = .declined(message)
        case .planned, .degraded:     screen = .plan
        }
    }
}

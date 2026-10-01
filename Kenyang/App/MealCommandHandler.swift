import Foundation

/// Carries out a button press from the Live Activity or the home-screen widget.
@MainActor
struct MealCommandHandler {
    let session: MealSession
    let coordinator: RoundCoordinator

    func handle(_ command: MealCommand) async {
        switch command {
        case .perform(let action):
            await perform(action)
        case .answer(let dish, let ingredient, let contains):
            coordinator.answer(ingredient, contains: contains, for: dish)
        }
    }

    private func perform(_ action: MealAction) async {
        switch action {
        case .startMeal:
            guard session.visit == nil else { return }
            session.start(at: DiningFocus.venueForNewMeal)
            await coordinator.planRound(advancing: false, within: LoopBudget.backgroundSeconds)
        case .endMeal:
            session.end(because: .unknown)
        case .good:
            session.rateNextDish(.good)
        case .skip:
            session.skipNextDish()
        case .nextRound:
            await coordinator.planRound(advancing: true, within: LoopBudget.backgroundSeconds)
        case .orderRound:
            session.acceptPlan()
        case .anotherRound:
            await coordinator.adjustRound(toward: nil, within: LoopBudget.backgroundSeconds)
        }
    }
}

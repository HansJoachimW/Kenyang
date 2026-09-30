import AppIntents
import Foundation
import UIKit

/// One press logs the next planned dish; a second press within eight seconds moves that
/// plate to the dish after it. It never rates: a blind press can't know how the food was.
struct LogNextItemIntent: AppIntent {
    static var title: LocalizedStringResource = "Log the next item"
    static var description = IntentDescription("Log the next dish in the planned round without opening the app. Press again within eight seconds to correct it.")
    static var openAppWhenRun = false
    static let correctionWindow: TimeInterval = 8

    @Dependency private var session: MealSession

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: Self.press(in: session)))
    }

    @MainActor
    static func press(in session: MealSession, at now: Date = .now) -> String {
        guard let visit = session.visit else { return "No meal in progress. Start a session first." }
        guard let plan = session.plan, !plan.isEmpty else { return "No round planned yet. Ask for a round first." }

        if let last = session.lastActionButtonPress, now.timeIntervalSince(last.at) <= correctionWindow {
            return moveLastPlate(last, plan: plan, visit: visit, session: session, at: now)
        }
        return logNextDish(plan: plan, visit: visit, session: session, at: now)
    }

    @MainActor
    private static func logNextDish(plan: RoundPlan, visit: Visit, session: MealSession, at now: Date) -> String {
        guard let next = session.nextDish(), let plate = session.logPlate(of: next.item) else {
            session.lastActionButtonPress = nil
            Haptics.tap(times: 1)
            return plan.needsAnswers
                ? "Ask staff about \(plan.dishesToAskAbout.joined(separator: ", ")) first, then answer in the app."
                : "Everything in this round is logged. Ask for another round when you are ready."
        }
        session.lastActionButtonPress = .init(plate: plate, itemIndex: next.index, at: now)
        Haptics.tap(times: 1)
        return StopGuard.stopMessage(for: visit)
            ?? "Logged \(next.item.dishName). \(CapacityEngine.state(for: visit).platesLeftSentence)"
    }

    @MainActor
    private static func moveLastPlate(_ last: MealSession.ActionButtonPress, plan: RoundPlan,
                                      visit: Visit, session: MealSession, at now: Date) -> String {
        let nextIndex = last.itemIndex + 1
        let previous = last.plate.dishName
        guard plan.items.indices.contains(nextIndex) else {
            Haptics.tap(times: 1)
            return "That was the last item in the round, so I have left it as \(previous)."
        }
        let item = plan.items[nextIndex]
        session.store.delete(last.plate)
        guard let plate = session.logPlate(of: item) else { return "\(item.dishName) is already fully logged." }
        session.lastActionButtonPress = .init(plate: plate, itemIndex: nextIndex, at: now)
        Haptics.tap(times: 2)
        return StopGuard.stopMessage(for: visit)
            ?? "Changed \(previous) to \(item.dishName). \(CapacityEngine.state(for: visit).platesLeftSentence)"
    }
}

/// One tap for a log, two for a correction. Only felt when the app is in the foreground;
/// with the phone locked the dialog is the feedback.
@MainActor
enum Haptics {
    static func tap(times: Int) {
        guard times > 0, UIApplication.shared.applicationState == .active else { return }
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        for step in 0..<times {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12 * Double(step)) {
                generator.impactOccurred()
            }
        }
    }
}

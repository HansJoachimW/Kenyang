import Foundation
import Testing
@testable import Kenyang

/// TEMPORARY — M2 feedback-loop probe through the diner's path. Delete after the measurement.
@MainActor
struct LoopProbe {
    @Test func theLoopCloses() async {
        for (meal, againstTheGuess) in [true, true, true, false, false].enumerated() {
            let store = KenyangStore(container: KenyangStore.makeContainer(inMemory: true))
            let session = MealSession(store: store, display: NoDisplay())
            let coordinator = RoundCoordinator(session: session)
            session.start()

            await coordinator.planRound(advancing: false)
            guard let guess = session.hypothesis, let plan = session.plan else { continue }
            session.acceptPlan()
            let testing = plan.items.filter { $0.category == guess.category }
            let rating: Rating = againstTheGuess ? .skip : guess.expectedRating
            for item in plan.items {
                session.logPlate(of: item)
                session.rate(item, item.category == guess.category ? rating : .fine)
            }
            print("LOOP meal \(meal + 1) — \(againstTheGuess ? "AGAINST" : "IN LINE"): guess \(guess.category.rawValue) expects \(guess.expectedRating.rawValue); round 1 planned \(testing.count) of it, rated \(rating.rawValue)")
            print("LOOP   round 1 plan: \(plan.items.map { "\($0.dishName) [\($0.category.rawValue)]" }.joined(separator: ", "))")

            let entriesBefore = session.trace.entries.count
            let started = Date.now
            await coordinator.planRound(advancing: true)
            print("LOOP   round 2 — \(String(format: "%.1f", Date.now.timeIntervalSince(started))) s")
            for entry in session.trace.entries.dropFirst(entriesBefore) where entry.kind != .toolCall || entry.title == "tools" {
                let override = entry.override.map { " {AI chose \($0.chose.rawValue) → Kenyang \($0.forced.rawValue)}" } ?? ""
                print("LOOP     \(entry.heading) [\(entry.isCalculated ? "calc" : "AI")]: \(entry.detail.prefix(160))\(override)")
            }
        }
    }
}

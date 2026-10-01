import Foundation
import Testing
@testable import Kenyang

@MainActor
struct RuleTests {
    @Test func avoidListVerdicts() {
        let prawn = DishSighting(name: "Prawn Tempura", category: .fried)
        let karubi = DishSighting(name: "Karubi", category: .meat)

        #expect(ExclusionValidator.verdict(for: prawn, avoiding: ["prawn"]) == .excluded)
        #expect(ExclusionValidator.verdict(for: karubi, avoiding: ["prawn"]) == .unknown)
        #expect(ExclusionValidator.verdict(for: karubi, avoiding: []) == .safe)

        karubi.clearedTerms = ["prawn"]
        #expect(ExclusionValidator.verdict(for: karubi, avoiding: ["prawn"]) == .safe)
    }

    @Test func aSkipGuessIsDisprovedByGoodRatings() {
        let posterior = DishPosterior(dishName: "Meat", category: .meat, mean: 1, sampleCount: 3, uncertainty: 0.25)

        #expect(ValueEngine.verdict(posterior, expecting: .skip) == .contradicted)
        #expect(ValueEngine.verdict(posterior, expecting: .good) == .supported)
    }

    @Test func oneRatingIsNotEnoughToJudge() {
        let posterior = DishPosterior(dishName: "Meat", category: .meat, mean: 0, sampleCount: 1, uncertainty: 0.5)

        #expect(ValueEngine.verdict(posterior, expecting: .good) == .insufficient)
    }

    @Test func stopGuardReasons() {
        let full = CapacityState(maxSatiety: 9, spent: 8.5)
        let roomy = CapacityState(maxSatiety: 9, spent: 1)

        #expect(StopGuard.reason(capacity: full, minutesRemaining: 60) == .capacityExhausted)
        #expect(StopGuard.reason(capacity: roomy, minutesRemaining: 0) == .seatingTimeOver)
        #expect(StopGuard.reason(capacity: roomy, minutesRemaining: 10) == .lastOrderPassed)
        #expect(StopGuard.reason(capacity: roomy, minutesRemaining: 60) == .none)
    }

    @Test func theFilterBlocksVolumeFraming() {
        #expect(!OutputValidator.isSafe("Keep eating until you are stuffed."))
        #expect(!OutputValidator.isSafe("Get your money\u{2019}s worth."))
        #expect(OutputValidator.isSafe("The grilled meat is where the value is tonight."))
    }

    @Test func adjustFallbackAlwaysMovesTheAskedWay() {
        let rejected = RoundIntent.balanced
        for direction in AdjustDirection.allCases {
            let adjusted = AdjustGuard.fallback(from: rejected, direction: direction)
            #expect(AdjustGuard.accepts(adjusted, rejected: rejected, direction: direction))
        }
    }

    @Test func untriedDishesAreOrderedOnceAndExcludedOnesNever() {
        let menu = testMenu.dishes.map { DishSighting(name: $0.name, category: $0.category, printedCategory: $0.section) }

        let plan = RoundPlanner.plan(objective: .balanced, candidates: menu, events: [],
                                     capacity: CapacityState(maxSatiety: 9, spent: 0), exclusions: ["prawn"])

        #expect(!plan.isEmpty)
        #expect(plan.items.allSatisfy { $0.quantity == 1 })
        #expect(!plan.items.contains { $0.dishName == "Prawn Tempura" })
    }

    @Test func planningTheFullMenuIsQuick() {
        let menu = BuffetMenu.default.dishes.map { DishSighting(name: $0.name, category: $0.category) }
        let started = Date.now

        let plan = RoundPlanner.plan(objective: .balanced, candidates: menu, events: [],
                                     capacity: CapacityState(maxSatiety: 12, spent: 0), exclusions: [])

        #expect(!plan.isEmpty)
        #expect(Date.now.timeIntervalSince(started) < 1)
    }

    @Test func aRoundTestsTheGuessWithTwoDishesFromItsCategory() {
        let menu = BuffetMenu.default.dishes.map {
            DishSighting(name: $0.name, category: $0.category, printedCategory: $0.section)
        }
        var objective = PlannerObjective.balanced
        objective.testCategory = .soup

        let plan = RoundPlanner.plan(objective: objective, candidates: menu, events: [],
                                     capacity: CapacityState(maxSatiety: 9, spent: 0), exclusions: [])

        #expect(plan.items.filter { $0.category == .soup }.count >= 2)
    }

    @Test func onlyAContradictedGuessChangesCourse() {
        let oneRating = DishPosterior(dishName: "Meat", category: .meat, mean: 0, sampleCount: 1, uncertainty: 0.5)
        let likedThrice = DishPosterior(dishName: "Meat", category: .meat, mean: 1, sampleCount: 3, uncertainty: 0.25)

        let untested = VerdictGuard.move(for: ValueEngine.verdict(oneRating, expecting: .good))
        let backed = VerdictGuard.move(for: ValueEngine.verdict(likedThrice, expecting: .good))
        let disproved = VerdictGuard.move(for: ValueEngine.verdict(likedThrice, expecting: .skip))

        #expect(untested == .exploit)
        #expect(backed == .exploit)
        #expect(disproved == .pivot)
    }

    @Test func theSpreadIsOneLinePerSection() {
        let menu = BuffetMenu.default.dishes.map {
            DishSighting(name: $0.name, category: $0.category, printedCategory: $0.section)
        }

        let lines = GetSpreadTool.sections(of: menu)

        #expect(lines.count == 8)
        #expect(lines.contains("SUSHI: raw 3 (usually liked, takes little room)"))
        #expect(lines.contains("APPETIZER & AGEMONO: fried 8 (seldom a favourite, takes a lot of room), vegetable 6 (sometimes liked, takes little room), soup 1 (sometimes liked, takes a lot of room)"))
    }

    @Test func mealsThatDidNotEndFullOnlyRaiseTheCapacityEstimate() {
        let store = KenyangStore(container: KenyangStore.makeContainer(inMemory: true))
        let short = store.startVisit(at: "Test", pricePerHead: 0, seatingMinutes: 90, maxSatiety: 9, dishes: [])
        store.addPlate(of: "Rice", category: .starch, rating: nil, round: 1, in: short)
        store.endVisit(short, because: .clock)

        #expect(CapacityEngine.fittedMax(from: [short], fallback: 9) == 9)
    }

    @Test func triageDeclinesOnlyWhenThereIsNothingToChoose() {
        let tiny = (1...5).map { DishSighting(name: "Dish \($0)", category: .meat) }
        let full = testMenu.dishes.map { DishSighting(name: $0.name, category: $0.category) }

        #expect(TriageGuard.shouldDecline(menu: tiny))
        #expect(!TriageGuard.shouldDecline(menu: full))
    }

    @Test func liveActivityPhase() {
        #expect(LiveActivityController.phase(isStopping: true, hasSuggestion: true, isEating: true, hasNextDish: true) == .timeToStop)
        #expect(LiveActivityController.phase(isStopping: false, hasSuggestion: true, isEating: false, hasNextDish: false) == .suggested)
        #expect(LiveActivityController.phase(isStopping: false, hasSuggestion: false, isEating: true, hasNextDish: true) == .eating)
        #expect(LiveActivityController.phase(isStopping: false, hasSuggestion: false, isEating: true, hasNextDish: false) == .roundDone)
        #expect(LiveActivityController.phase(isStopping: false, hasSuggestion: false, isEating: false, hasNextDish: false) == .planning)
    }

    @Test func theTierScreenRefusesBelowThreeVisits() {
        let restaurant = Restaurant(name: "Test", tierNames: ["Standard", "Premium"])

        guard case .insufficient(let visits, let needed, _, _) = TierEngine.verdict(for: restaurant) else {
            Issue.record("Expected a refusal")
            return
        }
        #expect(visits == 0)
        #expect(needed == TierEngine.minimumVisits)
    }
}

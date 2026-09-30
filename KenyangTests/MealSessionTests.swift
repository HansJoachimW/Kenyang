import Testing
@testable import Kenyang

@MainActor
struct MealSessionTests {
    @Test func skippingAnUneatenDishPassesWithoutSpendingRoom() throws {
        let session = makeSession()
        let edamame = plannedItem("Edamame", .vegetable)
        let visit = try #require(session.visit)
        let spentBefore = CapacityEngine.state(for: visit).spent

        let result = session.rate(edamame, .skip)

        #expect(result == .passed)
        #expect(session.platesEaten(of: edamame) == 0)
        #expect(session.rating(of: edamame) == .skip)
        #expect(CapacityEngine.state(for: visit).spent == spentBefore)
        #expect(!visit.tasteEvents.contains { $0.isRated })
    }

    @Test func skippingAfterEatingRatesThePlate() {
        let session = makeSession()
        let karubi = plannedItem("Karubi", .meat)
        session.logPlate(of: karubi)

        #expect(session.rate(karubi, .skip) == .rated(replacedEarlier: false))
        #expect(session.platesEaten(of: karubi) == 1)
    }

    @Test func nextDishMovesPastASkippedOne() {
        let session = makeSession()
        let edamame = plannedItem("Edamame", .vegetable)
        let karubi = plannedItem("Karubi", .meat)
        session.propose(plan(edamame, karubi))
        session.acceptPlan()

        session.rate(edamame, .skip)

        #expect(session.nextDish()?.item.dishName == "Karubi")
    }

    @Test func eatingASkippedDishTakesThePassBack() {
        let session = makeSession()
        let edamame = plannedItem("Edamame", .vegetable)
        session.rate(edamame, .skip)

        session.logPlate(of: edamame)

        #expect(session.platesEaten(of: edamame) == 1)
        #expect(session.rating(of: edamame) == nil)
    }

    @Test func platesStopAtWhatWasOrdered() {
        let session = makeSession()
        let karubi = plannedItem("Karubi", .meat)
        for _ in 0..<3 { session.logPlate(of: karubi) }

        #expect(session.platesEaten(of: karubi) == 1)
    }

    @Test func removingAPlateKeepsTheRatingWhilePlatesRemain() {
        let session = makeSession()
        let harami = plannedItem("Harami", .meat, orders: 2)
        session.logPlate(of: harami)
        session.logPlate(of: harami)
        session.rate(harami, .good)

        session.removePlate(of: harami)

        #expect(session.platesEaten(of: harami) == 1)
        #expect(session.rating(of: harami) == .good)
    }

    @Test func ratingTwiceReplacesTheFirstRating() {
        let session = makeSession()
        let karubi = plannedItem("Karubi", .meat)

        session.rate(karubi, .fine)
        let second = session.rate(karubi, .good)

        #expect(second == .rated(replacedEarlier: true))
        #expect(session.platesEaten(of: karubi) == 1)
        #expect(session.rating(of: karubi) == .good)
    }

    @Test func aRoundWithAnOpenIngredientQuestionCannotBeAccepted() {
        let session = makeSession()
        session.store.addExclusion("peanut")
        session.propose(plan(plannedItem("Karubi", .meat, needsCheck: true)))

        #expect(!session.acceptPlan())
        #expect(session.firstOpenQuestion()?.ingredient == "peanut")
    }

    @Test func answeringNoClearsTheDishAndYesRemovesIt() {
        let session = makeSession()
        session.store.addExclusion("peanut")
        session.propose(plan(plannedItem("Karubi", .meat, needsCheck: true),
                             plannedItem("Harami", .meat, needsCheck: true)))

        session.answer("peanut", contains: false, for: "Karubi")
        session.answer("peanut", contains: true, for: "Harami")

        #expect(session.plan?.items.map(\.dishName) == ["Karubi"])
        #expect(session.acceptPlan())
    }

    @Test func advancingARoundMovesEverySurfaceToIt() {
        let session = makeSession()
        session.beginRound(advancing: true)
        let karubi = plannedItem("Karubi", .meat)

        session.logPlate(of: karubi)

        #expect(session.round == 2)
        #expect(session.visit?.tasteEvents.first?.roundIndex == 2)
    }

    @Test func endingTheMealClearsTheSession() {
        let session = makeSession()
        session.propose(plan(plannedItem("Karubi", .meat)))

        session.end(because: .fullness)

        #expect(session.visit == nil)
        #expect(session.plan == nil)
        #expect(session.store.pastVisits().first?.endedBecause == .fullness)
    }
}

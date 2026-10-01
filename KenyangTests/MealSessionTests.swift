import Testing
@testable import Kenyang

@MainActor
struct MealSessionTests {
    @Test func skippingAnUneatenDishPassesWithoutSpendingRoom() throws {
        let session = makeSession()
        let edamame = plannedItem("Edamame", .vegetable)
        let visit = try #require(session.visit)
        let spentBefore = CapacityEngine.state(for: visit).spent

        session.skip(edamame)

        #expect(session.isSkipped(edamame))
        #expect(session.platesEaten(of: edamame) == 0)
        #expect(session.rating(of: edamame) == nil)
        #expect(CapacityEngine.state(for: visit).spent == spentBefore)
        #expect(!visit.tasteEvents.contains { $0.isRated })
    }

    @Test func skippingAfterEatingTakesThePlatesAndRatingBack() throws {
        let session = makeSession()
        let harami = plannedItem("Harami", .meat, orders: 2)
        let visit = try #require(session.visit)
        let spentBefore = CapacityEngine.state(for: visit).spent
        session.logPlate(of: harami)
        session.logPlate(of: harami)
        session.rate(harami, .good)

        session.skip(harami)

        #expect(session.platesEaten(of: harami) == 0)
        #expect(session.rating(of: harami) == nil)
        #expect(CapacityEngine.state(for: visit).spent == spentBefore)
    }

    @Test func didntLikeIsARatingOfAnEatenDish() {
        let session = makeSession()
        let karubi = plannedItem("Karubi", .meat)

        session.rate(karubi, .skip)

        #expect(session.platesEaten(of: karubi) == 1)
        #expect(session.rating(of: karubi) == .skip)
        #expect(!session.isSkipped(karubi))
    }

    @Test func loggingAPlateUpdatesTheRoomLeft() {
        let session = makeSession()
        let karubi = plannedItem("Karubi", .meat)

        let notified = notifiesRoomLeft(session) { session.logPlate(of: karubi) }

        #expect(notified)
    }

    @Test func removingAPlateUpdatesTheRoomLeft() {
        let session = makeSession()
        let karubi = plannedItem("Karubi", .meat)
        session.logPlate(of: karubi)

        let notified = notifiesRoomLeft(session) { session.removePlate(of: karubi) }

        #expect(notified)
    }

    @Test func nextDishMovesPastASkippedOne() {
        let session = makeSession()
        let edamame = plannedItem("Edamame", .vegetable)
        let karubi = plannedItem("Karubi", .meat)
        session.propose(plan(edamame, karubi))
        session.acceptPlan()

        session.skip(edamame)

        #expect(session.nextDish()?.item.dishName == "Karubi")
    }

    @Test func eatingASkippedDishTakesThePassBack() {
        let session = makeSession()
        let edamame = plannedItem("Edamame", .vegetable)
        session.skip(edamame)

        session.logPlate(of: edamame)

        #expect(session.platesEaten(of: edamame) == 1)
        #expect(session.rating(of: edamame) == nil)
        #expect(!session.isSkipped(edamame))
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

    @Test func changingANoAnswerAsksTheQuestionAgain() throws {
        let session = makeSession()
        session.store.addExclusion("peanut")
        session.propose(plan(plannedItem("Karubi", .meat, needsCheck: true)))
        let karubi = try #require(session.visit?.sighting(named: "Karubi"))
        session.answer("peanut", contains: false, for: "Karubi")

        session.reopen("peanut", for: "Karubi")

        #expect(session.clearedAnswers(for: karubi).isEmpty)
        #expect(session.firstOpenQuestion()?.ingredient == "peanut")
        #expect(!session.acceptPlan())
    }

    @Test func undoingAYesPutsTheDishBackWhereItWas() {
        let session = makeSession()
        session.store.addExclusion("peanut")
        session.propose(plan(plannedItem("Harami", .meat, needsCheck: true),
                             plannedItem("Karubi", .meat)))
        session.answer("peanut", contains: true, for: "Harami")

        session.reopen("peanut", for: "Harami")

        #expect(session.plan?.items.map(\.dishName) == ["Harami", "Karubi"])
        #expect(session.ruledOut.isEmpty)
        #expect(session.firstOpenQuestion()?.dish == "Harami")
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

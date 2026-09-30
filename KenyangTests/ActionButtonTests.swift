import Foundation
import Testing
@testable import Kenyang

@MainActor
struct ActionButtonTests {
    @Test func aPressLogsTheNextDishWithoutRatingIt() {
        let session = makeSession()
        session.propose(plan(plannedItem("Karubi", .meat), plannedItem("Edamame", .vegetable)))
        session.acceptPlan()

        _ = LogNextItemIntent.press(in: session)

        #expect(session.visit?.tasteEvents.map(\.dishName) == ["Karubi"])
        #expect(session.visit?.tasteEvents.contains { $0.isRated } == false)
    }

    @Test func aSecondPressInsideTheWindowMovesThePlate() {
        let session = makeSession()
        session.propose(plan(plannedItem("Karubi", .meat), plannedItem("Edamame", .vegetable)))
        session.acceptPlan()
        let now = Date.now

        _ = LogNextItemIntent.press(in: session, at: now)
        _ = LogNextItemIntent.press(in: session, at: now.addingTimeInterval(2))

        #expect(session.visit?.tasteEvents.map(\.dishName) == ["Edamame"])
    }
}

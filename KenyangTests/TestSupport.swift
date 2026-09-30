import Foundation
@testable import Kenyang

@MainActor
final class NoDisplay: MealDisplay {
    func show(_ session: MealSession) {}
    func clear(endedVisit: Visit, round: Int) {}
}

@MainActor
func makeSession() -> MealSession {
    let store = KenyangStore(container: KenyangStore.makeContainer(inMemory: true))
    let session = MealSession(store: store, display: NoDisplay())
    session.start(at: "Test Grill", pricePerHead: 100_000, menu: testMenu)
    return session
}

let testMenu = BuffetMenu(
    venueName: "Test Grill",
    tierName: "Standard",
    pricePerHead: 100_000,
    seatingMinutes: 90,
    dishes: [
        .init(name: "Karubi", category: .meat, section: "MEAT"),
        .init(name: "Harami", category: .meat, section: "MEAT"),
        .init(name: "Edamame", category: .vegetable, section: "APPETIZER"),
        .init(name: "Prawn Tempura", category: .fried, section: "APPETIZER"),
        .init(name: "Miso Soup", category: .soup, section: "SOUP"),
        .init(name: "Garlic Rice", category: .starch, section: "RICE"),
        .init(name: "Salmon Roll", category: .raw, section: "SUSHI"),
        .init(name: "Corn Foil", category: .vegetable, section: "GRILL"),
        .init(name: "Chicken Karaage", category: .fried, section: "APPETIZER"),
        .init(name: "Milk Pudding", category: .dessert, section: "DESSERT")
    ])

func plannedItem(_ name: String, _ category: MenuCategory, orders: Int = 1, needsCheck: Bool = false) -> PlannedItem {
    PlannedItem(dishName: name, category: category, portion: .normal, isRecon: orders == 1,
                satietyCost: category.satietyDensity * Double(orders), quantity: orders, needsCheck: needsCheck)
}

func plan(_ items: PlannedItem...) -> RoundPlan {
    RoundPlan(items: items, rationale: "Test", reconShare: .half, posture: .balanced)
}

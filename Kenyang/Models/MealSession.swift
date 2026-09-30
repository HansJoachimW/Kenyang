import Foundation
import Observation

/// Where the meal in progress is shown outside the app: the Live Activity and the widget.
@MainActor
protocol MealDisplay: AnyObject {
    func show(_ session: MealSession)
    func clear(endedVisit: Visit, round: Int)
}

/// The meal in progress: its round, its plan, and every way a plate is logged, rated or
/// skipped. The app, the Live Activity, Siri and the Action Button all go through here.
@MainActor
@Observable
final class MealSession {
    enum RatingResult: Equatable {
        case rated(replacedEarlier: Bool)
        case passed
    }

    struct ActionButtonPress {
        let plate: TasteEvent
        let itemIndex: Int
        let at: Date
    }

    let store: KenyangStore
    let trace = TraceLog()
    @ObservationIgnored private let display: MealDisplay?

    private(set) var plan: RoundPlan?
    private(set) var hypothesis: ValueHypothesis?
    private(set) var intent: RoundIntent?
    private(set) var note: String?
    private var chosenRound = 1
    private var passedDishes: Set<String> = []

    var lastActionButtonPress: ActionButtonPress?
    var isAskingWhyStopping = false

    init(store: KenyangStore, display: MealDisplay?) {
        self.store = store
        self.display = display
    }

    var visit: Visit? { store.activeVisit() }
    var isEating: Bool { visit?.outcome == .running }
    var round: Int { max(chosenRound, visit?.roundsPlayed ?? 1) }

    // MARK: - Starting and ending

    @discardableResult
    func start(at venueName: String = BuffetMenu.default.venueName,
               pricePerHead: Double = BuffetMenu.default.pricePerHead,
               menu: BuffetMenu = .default) -> Visit {
        let visit = store.startVisit(at: venueName,
                                     pricePerHead: pricePerHead,
                                     seatingMinutes: menu.seatingMinutes,
                                     maxSatiety: DinerPreferences.maxSatiety,
                                     dishes: menu.dishes)
        if let restaurant = visit.restaurant { ProactiveTrigger.shared.noteLocation(of: restaurant) }
        resetMealState()
        trace.clear()
        publish()
        return visit
    }

    func end(because ending: MealEnding) {
        guard let visit else { return }
        let finalRound = round
        store.endVisit(visit, because: ending)
        display?.clear(endedVisit: visit, round: finalRound)
        resetMealState()
    }

    // MARK: - Rounds

    func beginRound(advancing: Bool) {
        if advancing { chosenRound = round + 1 }
        plan = nil
        note = nil
        setOutcome(.planning)
    }

    func propose(_ plan: RoundPlan, hypothesis: ValueHypothesis? = nil, intent: RoundIntent? = nil, note: String? = nil) {
        self.plan = plan
        if let hypothesis { self.hypothesis = hypothesis }
        if let intent { self.intent = intent }
        self.note = note
        setOutcome(.planning)
    }

    func show(note: String?) {
        self.note = note
        publish()
    }

    @discardableResult
    func acceptPlan() -> Bool {
        guard let plan, !plan.isEmpty, !plan.needsAnswers else { return false }
        setOutcome(.running)
        return true
    }

    func setOrders(for item: PlannedItem, to quantity: Int) {
        guard let index = plan?.items.firstIndex(where: { $0.id == item.id }) else { return }
        let clamped = min(max(quantity, 1), RoundPlanner.maxOrdersPerDish)
        let costPerOrder = item.satietyCost / Double(item.quantity)
        plan?.items[index].quantity = clamped
        plan?.items[index].satietyCost = costPerOrder * Double(clamped)
        trace.record(.plan, "orders changed", "\(item.dishName): the diner set \(clamped) (planned \(item.quantity)).")
        publish()
    }

    /// The first dish in plan order that still has an order to eat and wasn't skipped.
    func nextDish() -> (item: PlannedItem, index: Int)? {
        guard let plan else { return nil }
        return plan.items.enumerated()
            .first { _, item in !item.needsCheck && !isPassed(item.dishName) && platesEaten(of: item) < item.quantity }
            .map { (item: $0.element, index: $0.offset) }
    }

    // MARK: - Plates and ratings

    func platesEaten(of item: PlannedItem) -> Int {
        guard let visit else { return 0 }
        return store.plates(of: item.dishName, round: round, in: visit).count
    }

    func rating(of item: PlannedItem) -> Rating? {
        guard let visit else { return nil }
        if let rated = store.plates(of: item.dishName, round: round, in: visit).first(where: \.isRated) {
            return rated.rating
        }
        return isPassed(item.dishName) ? .skip : nil
    }

    @discardableResult
    func logPlate(of item: PlannedItem) -> TasteEvent? {
        guard let visit, platesEaten(of: item) < item.quantity else { return nil }
        passedDishes.remove(passKey(item.dishName))
        let plate = store.addPlate(of: item.dishName, category: item.category, rating: nil, round: round, in: visit)
        publish()
        return plate
    }

    /// Removes the newest unrated plate first, so the dish keeps its rating while any
    /// plate of it is still logged.
    func removePlate(of item: PlannedItem) {
        guard let visit else { return }
        let plates = store.plates(of: item.dishName, round: round, in: visit).sorted { $0.at > $1.at }
        guard let plate = plates.first(where: { !$0.isRated }) ?? plates.first else { return }
        if lastActionButtonPress?.plate === plate { lastActionButtonPress = nil }
        store.delete(plate)
        publish()
    }

    /// One rating per dish per round. Skipping a dish nobody has eaten passes on it:
    /// no plate, no capacity spent, and no rating, because an order not eaten is not a
    /// taste.
    @discardableResult
    func rate(_ item: PlannedItem, _ rating: Rating) -> RatingResult {
        guard let visit else { return .passed }
        let plates = store.plates(of: item.dishName, round: round, in: visit)
        let result: RatingResult

        if rating == .skip {
            passedDishes.insert(passKey(item.dishName))
            guard !plates.isEmpty else {
                trace.record(.toolCall, "passed", "\(item.dishName) → skipped before eating, no plate logged")
                publish()
                return .passed
            }
        } else {
            passedDishes.remove(passKey(item.dishName))
        }

        if let rated = plates.first(where: \.isRated) {
            rated.rating = rating
            result = .rated(replacedEarlier: true)
        } else if let unrated = plates.first {
            unrated.rating = rating
            result = .rated(replacedEarlier: false)
        } else {
            store.addPlate(of: item.dishName, category: item.category, rating: rating, round: round, in: visit)
            result = .rated(replacedEarlier: false)
        }
        store.save()

        if result == .rated(replacedEarlier: false), let hypothesis, item.category == hypothesis.category {
            store.recordGuessOutcome(basis: hypothesis.basis, expected: hypothesis.expectedRating, actual: rating)
        }
        trace.record(.toolCall, "rateDish", "\(item.dishName) → \(rating.rawValue)")
        publish()
        return result
    }

    /// A plate logged by name, from Siri, whether or not it was planned.
    func logDish(named name: String, category: MenuCategory, rating: Rating?, portion: PortionBucket) {
        guard let visit else { return }
        store.addPlate(of: name, category: category, rating: rating, portion: portion, round: round, in: visit)
        publish()
    }

    /// The Live Activity's Good and Skip act on the next dish.
    func rateNextDish(_ rating: Rating) {
        guard let next = nextDish() else { return }
        if rating != .skip { logPlate(of: next.item) }
        rate(next.item, rating)
    }

    func recordFullness(_ fullness: Fullness) {
        guard let visit else { return }
        store.recordFullness(fullness.level, in: visit)
        trace.record(.toolCall, "fullness", "reported \(fullness.level)/5")
        publish()
    }

    // MARK: - The avoid list

    func openQuestions(for sighting: DishSighting) -> [String] {
        ExclusionValidator.openQuestions(for: sighting, avoiding: store.exclusions())
    }

    /// The first open ingredient question in the plan, for surfaces that ask one at a time.
    func firstOpenQuestion() -> (dish: String, ingredient: String)? {
        guard let plan, let visit else { return nil }
        for item in plan.items where item.needsCheck {
            if let sighting = visit.sighting(named: item.dishName),
               let ingredient = openQuestions(for: sighting).first {
                return (item.dishName, ingredient)
            }
        }
        return nil
    }

    /// A "no" clears the dish; a "yes" takes it off the plan and the rest of the round
    /// stands. Returns whether the answer left the plan empty.
    @discardableResult
    func answer(_ ingredient: String, contains: Bool, for dishName: String) -> Bool {
        guard let sighting = visit?.sighting(named: dishName) else { return false }
        store.recordAnswer(ingredient, contains: contains, for: sighting)
        trace.record(.guardrail, "exclusion resolved",
                     "\(dishName) · \(ingredient) → \(contains ? "contains it" : "cleared by the diner")")

        if let index = plan?.items.firstIndex(where: { $0.dishName == dishName }) {
            if contains {
                plan?.items.remove(at: index)
                trace.record(.plan, "dish removed", "\(dishName) contains \(ingredient). The rest of the round stands.")
            } else if openQuestions(for: sighting).isEmpty {
                plan?.items[index].needsCheck = false
            }
        }
        publish()
        return plan?.isEmpty == true
    }

    // MARK: - The AI's input

    func agentInput() -> AgentInput? {
        guard let visit else { return nil }
        return AgentInput(sightings: visit.sightings,
                          events: visit.tasteEvents,
                          capacity: CapacityEngine.state(for: visit),
                          minutesRemaining: visit.minutesRemaining,
                          exclusions: store.exclusions(),
                          basisRecords: store.basisRecords(),
                          roundIndex: round,
                          currentHypothesis: hypothesis,
                          fullnessReadings: visit.fullnessReadings)
    }

    // MARK: -

    func publish() {
        display?.show(self)
    }

    private func setOutcome(_ outcome: SessionOutcome) {
        visit?.outcome = outcome
        store.save()
        publish()
    }

    private func isPassed(_ dishName: String) -> Bool {
        passedDishes.contains(passKey(dishName))
    }

    private func passKey(_ dishName: String) -> String {
        "\(round)|\(dishName.lowercased())"
    }

    private func resetMealState() {
        plan = nil
        hypothesis = nil
        intent = nil
        note = nil
        chosenRound = 1
        passedDishes = []
        lastActionButtonPress = nil
        isAskingWhyStopping = false
    }
}

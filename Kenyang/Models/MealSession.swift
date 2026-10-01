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
    }

    struct ActionButtonPress {
        let plate: TasteEvent
        let itemIndex: Int
        let at: Date
    }

    /// A dish a "yes, it contains it" answer took off the plan, kept so the answer can be
    /// taken back until the round is accepted.
    struct RuledOutDish: Identifiable {
        let item: PlannedItem
        let ingredient: String
        let position: Int
        var id: String { "\(item.dishName)|\(ingredient)" }
    }

    let store: KenyangStore
    let trace = TraceLog()
    @ObservationIgnored private let display: MealDisplay?

    private(set) var plan: RoundPlan?
    private(set) var hypothesis: ValueHypothesis?
    private(set) var intent: RoundIntent?
    private(set) var note: String?
    private(set) var ruledOut: [RuledOutDish] = []
    private var chosenRound = 1
    private var passedDishes: Set<String> = []

    var lastActionButtonPress: ActionButtonPress?
    var isAskingWhyStopping = false

    init(store: KenyangStore, display: MealDisplay?) {
        self.store = store
        self.display = display
        visit = store.activeVisit()
    }

    /// Held rather than fetched on every read: a fetch inside a view's `body` hides every
    /// change read through it, which left the ring and the plate counts stale.
    private(set) var visit: Visit?
    var isEating: Bool { visit?.outcome == .running }
    var round: Int { max(chosenRound, visit?.roundsPlayed ?? 1) }

    // MARK: - Starting and ending

    @discardableResult
    func start(at venueName: String = BuffetMenu.default.venueName,
               pricePerHead: Double = BuffetMenu.default.pricePerHead,
               menu: BuffetMenu = .default) -> Visit {
        let started = store.startVisit(at: venueName,
                                       pricePerHead: pricePerHead,
                                       seatingMinutes: menu.seatingMinutes,
                                       maxSatiety: DinerPreferences.maxSatiety,
                                       dishes: menu.dishes)
        visit = started
        if let restaurant = started.restaurant { ProactiveTrigger.shared.noteLocation(of: restaurant) }
        resetMealState()
        trace.clear()
        publish()
        return started
    }

    func end(because ending: MealEnding) {
        guard let visit else { return }
        let finalRound = round
        store.endVisit(visit, because: ending)
        self.visit = nil
        display?.clear(endedVisit: visit, round: finalRound)
        resetMealState()
    }

    // MARK: - Rounds

    func beginRound(advancing: Bool) {
        if advancing { chosenRound = round + 1 }
        plan = nil
        note = nil
        ruledOut = []
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
        ruledOut = []
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
        return store.plates(of: item.dishName, round: round, in: visit).first(where: \.isRated)?.rating
    }

    func isSkipped(_ item: PlannedItem) -> Bool {
        isPassed(item.dishName)
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

    /// One rating per dish per round, and a rating means the dish was eaten: *skip* is
    /// "didn't like it", never "didn't have it". Returns nil when no meal is running.
    @discardableResult
    func rate(_ item: PlannedItem, _ rating: Rating) -> RatingResult? {
        guard let visit else { return nil }
        let plates = store.plates(of: item.dishName, round: round, in: visit)
        let result: RatingResult
        passedDishes.remove(passKey(item.dishName))

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

    /// The diner isn't having this dish: its plates this round come off, its rating goes,
    /// and no room is spent. Also undoes a plate or rating tapped by mistake.
    func skip(_ item: PlannedItem) {
        guard let visit else { return }
        for plate in store.plates(of: item.dishName, round: round, in: visit) {
            if lastActionButtonPress?.plate === plate { lastActionButtonPress = nil }
            store.delete(plate)
        }
        passedDishes.insert(passKey(item.dishName))
        trace.record(.toolCall, "passed", "\(item.dishName) → skipped, no plate kept")
        publish()
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
        logPlate(of: next.item)
        rate(next.item, rating)
    }

    func skipNextDish() {
        guard let next = nextDish() else { return }
        skip(next.item)
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
            if contains, let removed = plan?.items.remove(at: index) {
                ruledOut.append(RuledOutDish(item: removed, ingredient: ingredient, position: index))
                trace.record(.plan, "dish removed", "\(dishName) contains \(ingredient). The rest of the round stands.")
            } else if openQuestions(for: sighting).isEmpty {
                plan?.items[index].needsCheck = false
            }
        }
        publish()
        return plan?.isEmpty == true
    }

    /// Takes back an answer given by mistake. The question is asked again, and a dish a
    /// "yes" took off the plan goes back where it was.
    func reopen(_ ingredient: String, for dishName: String) {
        guard let sighting = visit?.sighting(named: dishName) else { return }
        store.forgetAnswer(ingredient, for: sighting)
        if let index = ruledOut.firstIndex(where: { $0.item.dishName == dishName && $0.ingredient == ingredient }) {
            let dish = ruledOut.remove(at: index)
            let position = min(dish.position, plan?.items.count ?? 0)
            plan?.items.insert(dish.item, at: position)
        }
        if let index = plan?.items.firstIndex(where: { $0.dishName == dishName }) {
            plan?.items[index].needsCheck = true
        }
        trace.record(.guardrail, "answer reopened", "\(dishName) · \(ingredient) → asked again")
        publish()
    }

    /// The avoid-list terms the diner said this dish doesn't contain.
    func clearedAnswers(for sighting: DishSighting) -> [String] {
        store.exclusions().filter(sighting.clearedTerms.contains)
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
        ruledOut = []
        lastActionButtonPress = nil
        isAskingWhyStopping = false
    }
}

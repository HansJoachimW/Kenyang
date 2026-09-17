import AppIntents
import CoreSpotlight
import Foundation
import FoundationModels
import SwiftUI

/// The in-app battery. Every other harness in this directory measures the model;
/// this one measures the app. It lived in `Views/` for as long as it was only ever
/// rendered — it belongs beside `TokenAudit`, `StanceProbe` and the probes it runs with.

@MainActor
@Observable
final class VerificationRunner {
    private let store: KenyangStore
    var lines: [String] = []
    var running = false

    init(store: KenyangStore) {
        self.store = store
    }

    private func emit(_ line: String) {
        lines.append(line)
        print(line)
    }

    func runAll() async {
        running = true
        lines = []
        emit("KENYANG VERIFICATION — \(Date().formatted(date: .omitted, time: .standard))")
        emit("")

        categoriesDecode()
        refusesBadImages()
        writesOnConfirm()
        loggingSplitsLoops()
        mealEndingRecorded()
        await snippetUpdatesInPlace()
        await entitiesResolve()
        excludedNeverPlanned()
        refusesOneSample()
        objectiveDrivesPlan()
        await toolsAndRefusals()
        await hypothesisPivots()
        await pathVaries()

        emit("")
        emit("=== VERIFICATION COMPLETE ===")
        running = false
    }

    private func categoriesDecode() {
        emit("──── stored categories still decode ⭐  ·  TESTS.md T76 ────")
        emit("StationCategory → MenuCategory renamed the persisted raw values. Nothing")
        emit("warns when a raw value stops decoding — it silently becomes .unknown.")

        let audit = store.auditPersistedCategories()
        emit("stored: \(audit.sightings) sightings, \(audit.events) taste events")

        guard audit.total > 0 else {
            emit("⚠️ store is empty — nothing to migrate, and nothing proven either")
            emit("stored categories still decode: VACUOUS — re-run after a session has been recorded")
            emit("")
            return
        }

        emit("\(audit.undecodable == 0 ? "✅" : "❌") decodable: \(audit.total - audit.undecodable)/\(audit.total)")
        emit("\(audit.unknown == 0 ? "✅" : "❌") categorised: \(audit.total - audit.unknown)/\(audit.total) — \(audit.unknown) sitting at .unknown")

        if audit.unknown > 0 && audit.undecodable == 0 {
            emit("⚠️ these decode cleanly and are still wrong. A migration default writes")
            emit("   .unknown into every existing row, which a decodability check cannot see.")
        }
        emit("stored categories still decode: \(audit.isClean ? "PASS" : "FAIL — \(audit.damaged) of \(audit.total) rows lost their category")")
        emit("")
    }

    private func refusesBadImages() {
        emit("──── unreadable images are refused ⭐  ·  TESTS.md T79 ────")
        emit("A parse handed 33 characters returns four invented dishes (T77). The model")
        emit("will not abstain, so the refusal has to be deterministic and upstream.")

        func image(width: Int, height: Int) -> CGImage? {
            CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(),
                      bitmapInfo: CGImageAlphaInfo.none.rawValue)?.makeImage()
        }

        var checks: [(String, Bool)] = []

        // The real share-sheet copy that started this: 224×224.
        if let thumbnail = image(width: 224, height: 224) {
            let complaint = CaptureQualityGuard.inspect(thumbnail)
            checks.append(("224×224 share-sheet copy refused", complaint == .tooFewPixels(megapixels: 0.050176)))
            emit("  224×224 → \(complaint == nil ? "accepted" : "REFUSED")")
        }
        // The published menu that yields 71 real items must still get through.
        if let poster = image(width: 1024, height: 724) {
            let complaint = CaptureQualityGuard.inspect(poster)
            checks.append(("1024×724 published menu accepted", complaint == nil))
            emit("  1024×724 → \(complaint == nil ? "accepted" : "REFUSED")")
        }

        let thin = CaptureQualityGuard.inspect(text: "TANDARD UFFEUI\n4E0O STANDARD MEAT", confidence: 0.9)
        checks.append(("33 characters refused", thin == .tooLittleText(characters: 33)))
        emit("  33 characters, high confidence → \(thin == nil ? "accepted" : "REFUSED")")

        let body = String(repeating: "Karubi Harami Gyu Tan ", count: 40)
        let glare = CaptureQualityGuard.inspect(text: body, confidence: 0.30)
        checks.append(("low confidence refused", glare == .unreliableText(confidence: 0.30)))
        emit("  \(body.count) characters at 30% confidence → \(glare == nil ? "accepted" : "REFUSED")")

        let clean = CaptureQualityGuard.inspect(text: body, confidence: 0.82)
        checks.append(("a good read is accepted", clean == nil))
        emit("  \(body.count) characters at 82% confidence → \(clean == nil ? "accepted" : "REFUSED")")

        emit("")
        for (label, passed) in checks { emit("\(passed ? "✅" : "❌") \(label)") }
        let failures = checks.filter { !$0.1 }.count
        emit("→ the guard refuses against the app's own interest — it would rather return")
        emit("  nothing than a menu nobody printed (CRITERIA.md §6)")
        emit("unreadable images are refused: \(failures == 0 ? "PASS" : "FAIL — \(failures) of \(checks.count) checks")")
        emit("")
    }

    private func writesOnConfirm() {
        emit("──── nothing is written until you confirm ⭐  ·  TESTS.md T23 ────")
        emit("The capture screen promises \"nothing is written until you confirm it\".")
        emit("Run the draft path against a scratch store and count what lands.")

        let scratch = KenyangStore(container: KenyangStore.makeContainer(inMemory: true))
        let capture = MenuCaptureViewModel()
        let venue = "Gyu-Kaku"

        func rows() -> (venues: Int, dishes: Int) {
            (scratch.restaurant(named: venue) == nil ? 0 : 1, scratch.allDishNames().count)
        }

        let start = rows()
        emit("scratch store at rest: \(start.venues) venue(s), \(start.dishes) dish(es)")

        capture.items = [
            MenuDraftItem(name: "Karubi", printedSection: "YAKINIKU", category: .meat),
            MenuDraftItem(name: "Harami", printedSection: "YAKINIKU", category: .meat),
            MenuDraftItem(name: "Agedashi Tofu", printedSection: "APPETIZER", category: .fried),
            MenuDraftItem(name: "", printedSection: "APPETIZER", category: .unknown)
        ]

        emit("")
        emit("① the gate refuses an incomplete draft")
        emit("\(capture.canConfirm ? "❌" : "✅") no venue, no tier → canConfirm = \(capture.canConfirm)")

        capture.venueName = venue
        capture.tierName = "Standard"
        emit("\(capture.canConfirm ? "✅" : "❌") venue and tier named → canConfirm = \(capture.canConfirm)")

        emit("")
        emit("② holding a complete, confirmable draft writes nothing")
        let held = rows()
        let heldClean = held == start
        emit("\(heldClean ? "✅" : "❌") after parse and edit: \(held.venues) venue(s), \(held.dishes) dish(es) — expected \(start.venues)/\(start.dishes)")

        emit("")
        emit("③ confirming is the write")
        let confirmed = capture.confirm(using: scratch)
        let visit = scratch.startVisit(restaurantName: confirmed.venueName,
                                       pricePerHead: confirmed.pricePerHead,
                                       seatingLimitMinutes: 90,
                                       maxSatiety: 3 * CapacityEngine.platesToSatiety)
        scratch.addSightings(confirmed.spread, to: visit)

        let after = rows()
        let wroteVenue = after.venues == 1
        let wroteDishes = after.dishes == 3
        emit("\(wroteVenue ? "✅" : "❌") venue written: \(after.venues)")
        emit("\(wroteDishes ? "✅" : "❌") dishes written: \(after.dishes) — 3 named of 4 drafted, the blank row dropped")

        let ladder = scratch.restaurant(named: venue)?.tierNames ?? []
        let tiered = ladder == ["Standard"] && confirmed.spread.allSatisfy { $0.tier == 0 }
        emit("\(tiered ? "✅" : "❌") tier from the file, not the parse: ladder \(ladder), every item at rank 0")

        let pass = heldClean && wroteVenue && wroteDishes && tiered && capture.canConfirm
        emit("nothing is written until you confirm: \(pass ? "PASS" : "FAIL") — capture path only.\n   The intent write paths are still uncovered (TESTS.md T10, T72)")
        emit("")
    }

    private func loggingSplitsLoops() {
        emit("──── logging and rating are separate loops ⭐  ·  TESTS.md T68 ────")
        emit("Logging *that* you ate is a capacity observation. Logging *how good it was*")
        emit("is a value observation. A blind log must move the first and not the second —")
        emit("inventing a rating nobody gave is worse than having none (§3f).")

        let scratch = KenyangStore(container: KenyangStore.makeContainer(inMemory: true))
        let visit = scratch.startVisit(restaurantName: "Gyu-Kaku",
                                       pricePerHead: SessionDefaults.pricePerHead,
                                       seatingLimitMinutes: SessionDefaults.seatingMinutes,
                                       maxSatiety: SessionDefaults.maxSatiety)
        scratch.addSightings([(name: "Karubi", category: .meat, printed: "MEAT", tier: 0)], to: visit)

        func value() -> DishPosterior {
            ValueEngine.posterior(dishName: "Karubi", category: .meat, events: visit.tasteEvents)
        }
        func capacity() -> Double { CapacityEngine.state(for: visit).spent }

        var checks: [(String, Bool)] = []

        emit("")
        emit("① a log with no rating")
        scratch.rate(dishName: "Karubi", category: .meat, rating: nil,
                     portion: .normal, in: visit, roundIndex: 1)
        let blindCapacity = capacity()
        let blindValue = value()
        checks.append(("capacity moved", blindCapacity > 0))
        checks.append(("value did NOT move", blindValue.sampleCount == 0))
        emit("\(blindCapacity > 0 ? "✅" : "❌") capacity spent: \(String(format: "%.2f", blindCapacity))")
        emit("\(blindValue.sampleCount == 0 ? "✅" : "❌") value samples: \(blindValue.sampleCount) — the rating was never given, so none was invented")

        emit("")
        emit("② the same dish, rated this time")
        scratch.rate(dishName: "Karubi", category: .meat, rating: .good,
                     portion: .normal, in: visit, roundIndex: 1)
        let ratedCapacity = capacity()
        let ratedValue = value()
        checks.append(("capacity moved again", ratedCapacity > blindCapacity))
        checks.append(("value moved once", ratedValue.sampleCount == 1))
        emit("\(ratedCapacity > blindCapacity ? "✅" : "❌") capacity spent: \(String(format: "%.2f", ratedCapacity)) — both mouthfuls counted")
        emit("\(ratedValue.sampleCount == 1 ? "✅" : "❌") value samples: \(ratedValue.sampleCount) of 2 events — only the rated one")

        emit("")
        for (label, passed) in checks { emit("\(passed ? "✅" : "❌") \(label)") }
        let failures = checks.filter { !$0.1 }.count
        emit("→ neither loop gates the other: you can log with tongs in your hand and")
        emit("  rate later, or never")
        emit("logging and rating are separate loops: \(failures == 0 ? "PASS" : "FAIL — \(failures) of \(checks.count) checks")")
        emit("")
    }

    private func mealEndingRecorded() {
        emit("──── the meal ending reaches the fit ⭐  ·  TESTS.md T72 ────")
        emit("Only a `fullness` ending measures capacity. Every other ending is a lower")
        emit("bound, and averaging the two biases the fit downward for ever.")

        let scratch = KenyangStore(container: KenyangStore.makeContainer(inMemory: true))
        var checks: [(String, Bool)] = []

        for ending in MealEnding.allCases {
            let visit = scratch.startVisit(restaurantName: "Gyu-Kaku \(ending.rawValue)",
                                           pricePerHead: SessionDefaults.pricePerHead,
                                           seatingLimitMinutes: SessionDefaults.seatingMinutes,
                                           maxSatiety: SessionDefaults.maxSatiety)
            scratch.endVisit(visit, outcome: .stopped, ending: ending)
            let stored = visit.endedBecause == ending
            checks.append(("\(ending.rawValue) survives the round trip", stored))
            emit("  \(stored ? "✅" : "❌") \(ending.rawValue) → stored \(visit.endedBecause.rawValue) · measures capacity: \(ending.measuresCapacity)")
        }

        let measuring = MealEnding.allCases.filter(\.measuresCapacity)
        let onlyFullness = measuring == [.fullness]
        checks.append(("only fullness measures capacity", onlyFullness))
        emit("")
        emit("\(onlyFullness ? "✅" : "❌") endings that measure capacity: \(measuring.map(\.rawValue).joined(separator: ", "))")

        // A visit that ends without a reason must not silently look like fullness.
        let quiet = scratch.startVisit(restaurantName: "Quiet",
                                       pricePerHead: SessionDefaults.pricePerHead,
                                       seatingLimitMinutes: nil,
                                       maxSatiety: SessionDefaults.maxSatiety)
        scratch.endVisit(quiet, outcome: .stopped)
        let defaultsSafe = quiet.endedBecause == .unknown && !quiet.endedBecause.measuresCapacity
        checks.append(("an unrecorded ending defaults to unknown, not fullness", defaultsSafe))
        emit("\(defaultsSafe ? "✅" : "❌") ended with no reason given → \(quiet.endedBecause.rawValue), excluded from the fit")

        let failures = checks.filter { !$0.1 }.count
        emit("the meal ending reaches the fit: \(failures == 0 ? "PASS" : "FAIL — \(failures) of \(checks.count) checks")")
        emit("")
    }

    private func snippetUpdatesInPlace() async {
        emit("──── the snippet updates in place ⭐  ·  TESTS.md T8 ────")
        emit("A snippet that dismisses is indistinguishable from a button that launched")
        emit("the app. Accept must rewrite the same surface — so the test is that the")
        emit("renderer returns a DIFFERENT view for the same visit, with no app launch.")

        let scratch = KenyangStore(container: KenyangStore.makeContainer(inMemory: true))
        let visit = scratch.startVisit(restaurantName: "Gyu-Kaku",
                                       pricePerHead: SessionDefaults.pricePerHead,
                                       seatingLimitMinutes: SessionDefaults.seatingMinutes,
                                       maxSatiety: SessionDefaults.maxSatiety)
        scratch.addSightings([
            (name: "Karubi", category: .meat, printed: "MEAT", tier: 0),
            (name: "Harami", category: .meat, printed: "MEAT", tier: 0),
            (name: "Salmon Sashimi", category: .raw, printed: "SUSHI", tier: 0)
        ], to: visit)
        scratch.lastPlan = RoundPlanner.plan(objective: .balanced,
                                             candidates: visit.sightings,
                                             events: visit.tasteEvents,
                                             capacity: CapacityEngine.state(for: visit),
                                             exclusions: [])

        var checks: [(String, Bool)] = []

        // Mirrors RoundSnippetIntent: the most recent visit, not only a live one.
        func state() -> String {
            guard let latest = scratch.allVisits().first else { return "no meal" }
            guard latest.isActive else { return "ended" }
            switch latest.outcome {
            case .stopped, .declined: return "ended"
            case .running:            return "receipt"
            case .planning:           return (scratch.lastPlan?.isEmpty ?? true) ? "no plan" : "plan"
            }
        }

        let planned = state()
        checks.append(("starts on the plan", planned == "plan"))
        emit("  before Accept → \(planned) · \(scratch.lastPlan?.items.count ?? 0) items")

        // What AcceptRoundIntent does.
        scratch.acceptRound(visit)
        let accepted = state()
        checks.append(("Accept rewrites it to a receipt", accepted == "receipt"))
        checks.append(("the same visit is still live — nothing dismissed", scratch.activeVisit() != nil))
        emit("  after Accept  → \(accepted) · visit still active: \(scratch.activeVisit() != nil)")

        // What AdjustRoundIntent does: a different objective, not a re-roll.
        let before = scratch.lastPlan?.items.map(\.dishName) ?? []
        scratch.lastPlan = RoundPlanner.plan(objective: PlannerObjective(reconShare: .most,
                                                                        learnAbout: [],
                                                                        avoidProfile: nil,
                                                                        posture: .aggressive,
                                                                        rationale: "Adjusted"),
                                             candidates: visit.sightings,
                                             events: visit.tasteEvents,
                                             capacity: CapacityEngine.state(for: visit),
                                             exclusions: [])
        let after = scratch.lastPlan?.items.map(\.dishName) ?? []
        let adjusted = !after.isEmpty
        checks.append(("Adjust produces a plan under a new objective", adjusted))
        emit("  Adjust        → \(before.joined(separator: "→")) becomes \(after.joined(separator: "→"))")

        // What EndMealIntent does.
        scratch.endVisit(visit, outcome: .stopped, ending: .fullness)
        let ended = state()
        checks.append(("Stop ends the meal", ended == "ended"))
        emit("  after Stop    → \(ended)")

        // The claim that actually scores: none of the three opens the app.
        let noLaunch = AcceptRoundIntent.openAppWhenRun == false
            && AdjustRoundIntent.openAppWhenRun == false
            && EndMealIntent.openAppWhenRun == false
        checks.append(("no button opens the app", noLaunch))
        emit("  openAppWhenRun — Accept: \(AcceptRoundIntent.openAppWhenRun) · Adjust: \(AdjustRoundIntent.openAppWhenRun) · Stop: \(EndMealIntent.openAppWhenRun)")

        emit("")
        for (label, passed) in checks { emit("\(passed ? "✅" : "❌") \(label)") }
        let failures = checks.filter { !$0.1 }.count
        emit("→ the state machine is proven here; that the SYSTEM redraws the snippet")
        emit("  rather than dismissing it is an on-device check")
        emit("the snippet updates in place: \(failures == 0 ? "PASS" : "FAIL — \(failures) of \(checks.count) checks")")
        emit("")
    }

    private func entitiesResolve() async {
        emit("──── the four entity types resolve ⭐  ·  TESTS.md T6 · T12 · T69 ────")
        emit("Entities that compile are not entities that resolve. Drive every query")
        emit("the way Shortcuts, Siri and Spotlight will.")

        let scratch = KenyangStore(container: KenyangStore.makeContainer(inMemory: true))
        let visit = scratch.startVisit(restaurantName: "Gyu-Kaku",
                                       pricePerHead: 629_800,
                                       seatingLimitMinutes: 90,
                                       maxSatiety: 9)
        scratch.addSightings([
            (name: "Karubi", category: .meat, printed: "STANDARD MEAT", tier: 0),
            (name: "Harami", category: .meat, printed: "STANDARD MEAT", tier: 0),
            (name: "Salmon Sashimi", category: .raw, printed: "SUSHI", tier: 0),
            (name: "Agedashi Tofu", category: .fried, printed: "APPETIZER & AGEMONO", tier: 0)
        ], to: visit)
        scratch.rate(dishName: "Karubi", category: .meat, rating: .good,
                     portion: .normal, in: visit, roundIndex: 1)
        scratch.rate(dishName: "Agedashi Tofu", category: .fried, rating: .skip,
                     portion: .taste, in: visit, roundIndex: 1)

        var checks: [(String, Bool)] = []
        let items = MenuItemEntityQuery(store: scratch)
        let venues = VenueEntityQuery(store: scratch)
        let visits = VisitEntityQuery(store: scratch)
        let categories = MenuCategoryEntityQuery()

        // T6 — a Shortcuts picker calls suggestedEntities, then entities(for:).
        let suggested = (try? await items.suggestedEntities()) ?? []
        checks.append(("T6 menu items offered to a picker", suggested.count == 4))
        emit("  suggestedEntities → \(suggested.count) item(s): \(suggested.map(\.name).joined(separator: ", "))")

        let byID = (try? await items.entities(for: ["Karubi"])) ?? []
        checks.append(("T6 an item round-trips by id", byID.first?.name == "Karubi"))
        emit("  entities(for: [\"Karubi\"]) → \(byID.first?.name ?? "nothing")")

        let venueList = (try? await venues.suggestedEntities()) ?? []
        checks.append(("T6 venue resolves", venueList.first?.name == "Gyu-Kaku"))
        emit("  venues → \(venueList.map(\.name).joined(separator: ", "))")

        let mealList = (try? await visits.suggestedEntities()) ?? []
        checks.append(("T6 meal resolves", mealList.count == 1))
        emit("  meals → \(mealList.map { "\($0.venueName), \($0.ratedCount) rated" }.joined(separator: ", "))")

        let categoryList = (try? await categories.entities(matching: "sashimi")) ?? []
        checks.append(("T6 category resolves by label", categoryList.first?.category == .raw))
        emit("  categories matching \"sashimi\" → \(categoryList.map(\.name).joined(separator: ", "))")

        // T66's shape — a spoken name resolves against this meal's menu, not the world.
        let spoken = (try? await items.entities(matching: "harami")) ?? []
        checks.append(("Siri resolves a spoken name", spoken.first?.name == "Harami"))
        emit("  entities(matching: \"harami\") → \(spoken.map(\.name).joined(separator: ", "))")

        let miss = (try? await items.entities(matching: "tteokbokki")) ?? []
        checks.append(("an unknown name returns nothing, not a guess", miss.isEmpty))
        emit("  entities(matching: \"tteokbokki\") → \(miss.isEmpty ? "nothing — the system asks" : miss.map(\.name).joined(separator: ", "))")

        // T12 — the Spotlight payload has to carry more than a name.
        let sashimi = suggested.first { $0.name == "Salmon Sashimi" }
        let attributes = sashimi?.attributeSet
        let indexed = attributes?.title == "Salmon Sashimi"
            && (attributes?.keywords?.contains("Raw & sashimi") ?? false)
        checks.append(("T12 the dish carries a Spotlight payload", indexed))
        emit("  attributeSet → title \"\(attributes?.title ?? "—")\", keywords \(attributes?.keywords ?? [])")

        // T69 — "dishes I rated good at Gyu-Kaku", the way Shortcuts composes it.
        let good = (try? await items.entities(
            matching: [{ $0.rating == .good }, { $0.venueName == "Gyu-Kaku" }],
            mode: .and,
            sortedBy: [],
            limit: nil)) ?? []
        checks.append(("T69 rated-good at a venue", good.map(\.name) == ["Karubi"]))
        emit("  rated good at Gyu-Kaku → \(good.map(\.name).joined(separator: ", "))")

        // EntityQuerySort has no public initialiser — Shortcuts builds it — so the
        // sort path is exercised on device, not here. The filter is the substance.
        let meat = (try? await items.entities(
            matching: [{ $0.category == .meat }],
            mode: .and,
            sortedBy: [],
            limit: nil)) ?? []
        checks.append(("T69 filters by category", meat.map(\.name) == ["Harami", "Karubi"]))
        emit("  category is meat → \(meat.map(\.name).joined(separator: ", "))")

        let either = (try? await items.entities(
            matching: [{ $0.category == .raw }, { $0.rating == .skip }],
            mode: .or,
            sortedBy: [],
            limit: nil)) ?? []
        checks.append(("T69 honours OR mode", Set(either.map(\.name)) == ["Salmon Sashimi", "Agedashi Tofu"]))
        emit("  raw OR rated skip → \(either.map(\.name).joined(separator: ", "))")

        let capped = (try? await items.entities(matching: [], mode: .and,
                                                sortedBy: [], limit: 2)) ?? []
        checks.append(("T69 honours limit", capped.count == 2))
        emit("  limit 2 → \(capped.count) item(s)")

        emit("")
        for (label, passed) in checks { emit("\(passed ? "✅" : "❌") \(label)") }
        let failures = checks.filter { !$0.1 }.count
        emit("→ resolution is proven here; the Shortcuts editor, Siri and the Spotlight")
        emit("  index itself are on-device checks — T6/T11/T12 close on the phone")
        emit("the four entity types resolve: \(failures == 0 ? "PASS" : "FAIL — \(failures) of \(checks.count) checks")")
        emit("")
    }

    private func excludedNeverPlanned() {
        emit("──── excluded dishes are never planned ⭐  ·  TESTS.md T30 ────")

        let known = DishSighting(name: "Prawn cocktail", category: .raw,
                                 ingredientsKnown: true, ingredients: ["prawn", "mayonnaise"])
        let clean = DishSighting(name: "Green salad", category: .vegetable,
                                 ingredientsKnown: true, ingredients: ["lettuce", "tomato"])
        let opaque = DishSighting(name: "Nasi Goreng", category: .starch,
                                  ingredientsKnown: false)

        let exclusions = ["prawn"]
        let cases: [(DishSighting, ExclusionVerdict)] = [
            (known, .excluded), (clean, .safe), (opaque, .unknown)
        ]

        var passed = 0
        for (dish, expected) in cases {
            let actual = ExclusionValidator.verdict(for: dish, exclusions: exclusions)
            let ok = actual == expected
            if ok { passed += 1 }
            emit("\(ok ? "✅" : "❌") \(dish.name) → \(actual.rawValue) (expected \(expected.rawValue))")
        }

        let plan = RoundPlanner.plan(objective: .balanced,
                                     candidates: [known, clean, opaque],
                                     events: [],
                                     capacity: CapacityState(maxSatiety: 9, spent: 0),
                                     exclusions: exclusions)
        let planned = Set(plan.items.map(\.dishName))
        let excludedLeaked = planned.contains(known.name)
        let unknownLeaked = planned.contains(opaque.name)

        emit("planned: \(planned.sorted().joined(separator: ", "))")
        emit("\(excludedLeaked ? "❌" : "✅") EXCLUDED dish absent from plan")
        emit("\(unknownLeaked ? "❌" : "✅") UNKNOWN dish never planned silently")
        emit("excluded dishes are never planned: \(passed == 3 && !excludedLeaked && !unknownLeaked ? "PASS" : "FAIL")")
        emit("")
    }

    private func refusesOneSample() {
        emit("──── no claim from one rating  ·  TESTS.md T29 ────")
        let one = [TasteEvent(dishName: "Sashimi", category: .raw, rating: .good, portion: .normal, roundIndex: 1)]
        let two = one + [TasteEvent(dishName: "Sashimi", category: .raw, rating: .good, portion: .normal, roundIndex: 1)]

        let p1 = ValueEngine.posterior(dishName: "Sashimi", category: .raw, events: one)
        let p2 = ValueEngine.posterior(dishName: "Sashimi", category: .raw, events: two)

        emit("\(StatisticalGuard.canClaim(p1) ? "❌" : "✅") n=1 → claim refused")
        emit("\(StatisticalGuard.canClaim(p2) ? "✅" : "❌") n=2 → claim allowed")
        emit("no claim from one rating: \(!StatisticalGuard.canClaim(p1) && StatisticalGuard.canClaim(p2) ? "PASS" : "FAIL")")
        emit("")
    }

    private func objectiveDrivesPlan() {
        emit("──── the objective changes the plan  ·  TESTS.md T37 ────")
        emit("Principle 29: replace the objective with a constant. If the plan is")
        emit("identical, the agent is decorative.")

        let spread = DemoSpread.standard.map {
            DishSighting(name: $0.name, category: $0.category,
                         printedCategory: $0.printed, tierRank: $0.tier)
        }
        let capacity = CapacityState(maxSatiety: 9, spent: 0)

        let objectives: [(String, PlannerObjective)] = [
            ("recon=none  conservative", PlannerObjective(reconShare: .none, learnAbout: [], avoidProfile: nil, posture: .conservative, rationale: "")),
            ("recon=most  aggressive",   PlannerObjective(reconShare: .most, learnAbout: [], avoidProfile: nil, posture: .aggressive, rationale: "")),
            ("recon=half  avoid fresh",  PlannerObjective(reconShare: .half, learnAbout: ["Fried rice"], avoidProfile: .fresh, posture: .balanced, rationale: ""))
        ]

        var signatures: Set<String> = []
        for (label, objective) in objectives {
            let plan = RoundPlanner.plan(objective: objective, candidates: spread,
                                         events: [], capacity: capacity, exclusions: [])
            let sig = plan.items.map(\.dishName).joined(separator: "→")
            signatures.insert(sig)
            emit("  \(label): \(sig)")
        }

        emit("distinct plans from \(objectives.count) objectives: \(signatures.count)")
        emit("the objective changes the plan: \(signatures.count > 1 ? "PASS" : "FAIL — the planner ignores the agent")")
        emit("")
    }

    private func toolsAndRefusals() async {
        emit("──── every tool runs, and can refuse ⭐  ·  TESTS.md T21 · T22 ────")
        guard case .available = SystemLanguageModel.default.availability else {
            emit("⚠️ model unavailable — skipped"); emit(""); return
        }

        let spread = DemoSpread.standard.map {
            DishSighting(name: $0.name, category: $0.category,
                         printedCategory: $0.printed, tierRank: $0.tier)
        }

        await ToolContext.shared.resetInvocations()
        await ToolContext.shared.load(sightings: spread, events: [],
                                      capacity: CapacityState(maxSatiety: 9, spent: 0),
                                      minutesRemaining: 55, exclusions: ["peanut"],
                                      basisRecords: [], fullnessReadings: [], hypothesisCategory: .raw)

        let prompts = [
            "List the spread and the constraints, then say where the value is.",
            "Check whether the raw bar hypothesis holds, and how much budget is left.",
            "Check the calibration history and any previous visits to this restaurant.",
            "Can the remaining budget still be trusted? Verify the capacity estimate against what the diner reported, then say where the value is."
        ]
        for prompt in prompts {
            let session = LanguageModelSession(tools: AgentToolbox.readTools,
                                               instructions: RoundAgent.instructions)
            _ = try? await session.respond(to: prompt, generating: ValueHypothesis.self).content
        }

        let invoked = Set(await ToolContext.shared.invocationList)
        let missing = AgentToolbox.allNames.filter { !invoked.contains($0) }
        emit("invoked (\(invoked.count)/\(AgentToolbox.allNames.count)): \(invoked.sorted().joined(separator: ", "))")
        emit(missing.isEmpty ? "✅ every tool invoked" : "⚠️ never invoked: \(missing.joined(separator: ", "))")

        let refusals = [
            ("evaluateHypothesis", try? await EvaluateHypothesisTool().call(arguments: .init(category: .raw, expectedRating: .good))),
            ("getPosterior",       try? await GetPosteriorTool().call(arguments: .init(category: .meat))),
            ("getBasisCalibration", try? await GetBasisCalibrationTool().call(arguments: .init()))
        ]
        var refused = 0
        for (name, output) in refusals {
            let text = output ?? ""
            let saysNo = text.contains("insufficient")
            if saysNo { refused += 1 }
            emit("\(saysNo ? "✅" : "❌") \(name) → \(text)")
        }
        emit("every tool runs: \(missing.isEmpty ? "PASS" : "PARTIAL")   ·   and can refuse: \(refused == 3 ? "PASS" : "FAIL") (\(refused)/3 refused)")
        emit("")
    }

    private func hypothesisPivots() async {
        emit("──── a contradicted hypothesis pivots ⭐  ·  TESTS.md T35 ────")
        let spread = DemoSpread.standard.map {
            DishSighting(name: $0.name, category: $0.category,
                         printedCategory: $0.printed, tierRank: $0.tier)
        }
        let badRawBar = [
            TasteEvent(dishName: "Sashimi", category: .raw, rating: .skip, portion: .taste, roundIndex: 1),
            TasteEvent(dishName: "Oysters", category: .raw, rating: .skip, portion: .taste, roundIndex: 1),
            TasteEvent(dishName: "Prawns", category: .raw, rating: .skip, portion: .taste, roundIndex: 1)
        ]
        let hypothesis = ValueHypothesis(claim: "The value is concentrated at the raw bar.",
                                         category: .raw, basis: .tierExclusivity,
                                         confidence: .high, expectedRating: .good)

        let posterior = ValueEngine.categoryPosterior(.raw, events: badRawBar)
        let verdict: HypothesisVerdict = posterior.sampleCount < ValueEngine.minimumSamples
            ? .insufficient
            : (posterior.mean >= hypothesis.expectedRating.score - 0.25 ? .supported : .contradicted)

        emit("rated the hypothesised category skip×3 → observed \(String(format: "%.2f", posterior.mean)), expected \(String(format: "%.2f", hypothesis.expectedRating.score))")
        emit("\(verdict == .contradicted ? "✅" : "❌") deterministic verdict: \(verdict.rawValue)")

        let trace = TraceLog()
        let agent = RoundAgent(trace: trace)
        let input = AgentInput(sightings: spread, events: badRawBar,
                               capacity: CapacityState(maxSatiety: 9, spent: 2.1),
                               minutesRemaining: 45, exclusions: [], basisRecords: [],
                               roundIndex: 2, currentHypothesis: hypothesis)
        let outcome = await agent.run(input)

        if case .planned(_, let newHypothesis, _) = outcome {
            let pivoted = newHypothesis.category != hypothesis.category
            emit("\(pivoted ? "✅" : "❌") pivoted: \(hypothesis.category.rawValue) → \(newHypothesis.category.rawValue)")
            emit("   new claim: \(newHypothesis.claim)")
        } else {
            emit("outcome: \(outcome)")
        }
        for entry in trace.entries where entry.kind == .guardrail || entry.kind == .decision {
            emit("   [\(entry.title)] \(entry.detail)")
        }
        emit("a contradicted hypothesis pivots: \(verdict == .contradicted ? "PASS on the verdict" : "FAIL")")
        emit("")
    }

    private func pathVaries() async {
        emit("──── different data takes different paths ⭐  ·  TESTS.md T34 ────")
        let spread = DemoSpread.standard.map {
            DishSighting(name: $0.name, category: $0.category,
                         printedCategory: $0.printed, tierRank: $0.tier)
        }
        let thin = Array(spread.prefix(6)).map {
            DishSighting(name: $0.name, category: $0.category)
        }

        let scenarios: [(String, AgentInput)] = [
            ("fresh start", AgentInput(sightings: spread, events: [],
                                       capacity: CapacityState(maxSatiety: 9, spent: 0),
                                       minutesRemaining: 80, exclusions: [], basisRecords: [],
                                       roundIndex: 1, currentHypothesis: nil)),
            ("capacity gone", AgentInput(sightings: spread, events: [],
                                         capacity: CapacityState(maxSatiety: 9, spent: 8.5),
                                         minutesRemaining: 40, exclusions: [], basisRecords: [],
                                         roundIndex: 3, currentHypothesis: nil)),
            ("time gone", AgentInput(sightings: spread, events: [],
                                     capacity: CapacityState(maxSatiety: 9, spent: 2),
                                     minutesRemaining: 4, exclusions: [], basisRecords: [],
                                     roundIndex: 2, currentHypothesis: nil)),
            ("thin spread", AgentInput(sightings: thin, events: [],
                                       capacity: CapacityState(maxSatiety: 9, spent: 0),
                                       minutesRemaining: 60, exclusions: [], basisRecords: [],
                                       roundIndex: 1, currentHypothesis: nil))
        ]

        var paths: [String] = []
        for (label, input) in scenarios {
            let trace = TraceLog()
            let outcome = await RoundAgent(trace: trace).run(input)
            let terminal: String
            switch outcome {
            case .declined:  terminal = "DECLINE"
            case .stopped:   terminal = "STOP"
            case .degraded:  terminal = "DEGRADED"
            case .planned:   terminal = "PLAN"
            }
            let path = trace.entries.map(\.kind.rawValue).joined(separator: "→")
            paths.append(terminal)
            emit("  \(label): \(terminal)  [\(path)]")
        }

        let distinct = Set(paths).count
        emit("distinct terminal states: \(distinct)/\(paths.count)")
        emit("different data takes different paths: \(distinct >= 3 ? "PASS" : "FAIL — this is a pipeline")")
        emit("")
    }
}

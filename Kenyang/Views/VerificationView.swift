import AppIntents
import CoreSpotlight
import Foundation
import FoundationModels
import SwiftUI

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

        t76_vocabularyMigration()
        t79_captureQualityGuard()
        t23_confirmationGate()
        await t6_t12_t69_entityQueries()
        t30_exclusionValidator()
        t29_minimumSamples()
        t37_counterfactual()
        await t21_t22_toolCoverage()
        await t35_hypothesisDeath()
        await t34_pathVariance()

        emit("")
        emit("=== VERIFICATION COMPLETE ===")
        running = false
    }

    private func t76_vocabularyMigration() {
        emit("──── T76 ⭐ vocabulary migration — no stored category decodes to unknown ────")
        emit("StationCategory → MenuCategory renamed the persisted raw values. Nothing")
        emit("warns when a raw value stops decoding — it silently becomes .unknown.")

        let audit = store.auditPersistedCategories()
        emit("stored: \(audit.sightings) sightings, \(audit.events) taste events")

        guard audit.total > 0 else {
            emit("⚠️ store is empty — nothing to migrate, and nothing proven either")
            emit("T76: VACUOUS — re-run after a session has been recorded")
            emit("")
            return
        }

        emit("\(audit.undecodable == 0 ? "✅" : "❌") decodable: \(audit.total - audit.undecodable)/\(audit.total)")
        emit("\(audit.unknown == 0 ? "✅" : "❌") categorised: \(audit.total - audit.unknown)/\(audit.total) — \(audit.unknown) sitting at .unknown")

        if audit.unknown > 0 && audit.undecodable == 0 {
            emit("⚠️ these decode cleanly and are still wrong. A migration default writes")
            emit("   .unknown into every existing row, which a decodability check cannot see.")
        }
        emit("T76: \(audit.isClean ? "PASS" : "FAIL — \(audit.damaged) of \(audit.total) rows lost their category")")
        emit("")
    }

    private func t79_captureQualityGuard() {
        emit("──── T79 ⭐ capture refuses what it cannot read ────")
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
        emit("T79: \(failures == 0 ? "PASS" : "FAIL — \(failures) of \(checks.count) checks")")
        emit("")
    }

    private func t23_confirmationGate() {
        emit("──── T23 ⭐ no write without confirmation — the capture path ────")
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
        emit("T23: \(pass ? "PASS" : "FAIL") — capture path only. The intent write paths are T10/T72")
        emit("")
    }

    private func t6_t12_t69_entityQueries() async {
        emit("──── T6 · T12 ⭐ · T69 — the four entity types resolve ────")
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
        emit("T6/T12/T69: \(failures == 0 ? "PASS" : "FAIL — \(failures) of \(checks.count) checks")")
        emit("")
    }

    private func t30_exclusionValidator() {
        emit("──── T30 ⭐ exclusion validator, ternary ────")

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
        emit("T30: \(passed == 3 && !excludedLeaked && !unknownLeaked ? "PASS" : "FAIL")")
        emit("")
    }

    private func t29_minimumSamples() {
        emit("──── T29 statistical guard — no claim at n=1 ────")
        let one = [TasteEvent(dishName: "Sashimi", category: .raw, rating: .good, portion: .normal, roundIndex: 1)]
        let two = one + [TasteEvent(dishName: "Sashimi", category: .raw, rating: .good, portion: .normal, roundIndex: 1)]

        let p1 = ValueEngine.posterior(dishName: "Sashimi", category: .raw, events: one)
        let p2 = ValueEngine.posterior(dishName: "Sashimi", category: .raw, events: two)

        emit("\(StatisticalGuard.canClaim(p1) ? "❌" : "✅") n=1 → claim refused")
        emit("\(StatisticalGuard.canClaim(p2) ? "✅" : "❌") n=2 → claim allowed")
        emit("T29: \(!StatisticalGuard.canClaim(p1) && StatisticalGuard.canClaim(p2) ? "PASS" : "FAIL")")
        emit("")
    }

    private func t37_counterfactual() {
        emit("──── T37 counterfactual — does the model's output change the plan? ────")
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
        emit("T37: \(signatures.count > 1 ? "PASS — the objective drives the plan" : "FAIL — planner ignores the agent")")
        emit("")
    }

    private func t21_t22_toolCoverage() async {
        emit("──── T21/T22 ⭐ tool coverage and refusals ────")
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
        emit("T21: \(missing.isEmpty ? "PASS" : "PARTIAL")   T22: \(refused == 3 ? "PASS" : "FAIL") (\(refused)/3 refused)")
        emit("")
    }

    private func t35_hypothesisDeath() async {
        emit("──── T35 ⭐ a hypothesis dying ────")
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
        emit("T35: \(verdict == .contradicted ? "PASS on the verdict" : "FAIL")")
        emit("")
    }

    private func t34_pathVariance() async {
        emit("──── T34 ⭐ path variance ────")
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
        emit("T34: \(distinct >= 3 ? "PASS — path varies with the data" : "FAIL — pipeline")")
        emit("")
    }
}

private struct Harness: Identifiable {
    let id: String
    let name: String
    let detail: String
    let rendersInApp: Bool
    let run: @MainActor () async -> Void
}

struct VerificationView: View {
    @Environment(\.kenyangStore) private var store
    @State private var runner: VerificationRunner?
    @State private var active: String?
    @State private var elapsed: [String: Duration] = [:]

    var body: some View {
        NavigationStack {
            Group {
                if let runner {
                    list(runner)
                } else {
                    ProgressView().task { runner = VerificationRunner(store: store) }
                }
            }
            .navigationTitle("Verification")
        }
    }

    private func list(_ runner: VerificationRunner) -> some View {
        List {
            Section {
                ForEach(harnesses(runner)) { harness in
                    row(harness)
                }
            } header: {
                Text("Harnesses")
            } footer: {
                Text("Only the app battery renders here. Every other harness prints to the Xcode console. Each row is also reachable headlessly as a launch argument, which measures in a clean process.")
            }

            Section {
                Button {
                    runSequence(harnesses(runner))
                } label: {
                    Label("Run every harness", systemImage: "play.rectangle.on.rectangle")
                }
                .disabled(active != nil)
            } footer: {
                Text("Runs all seven in order. Around twelve minutes.")
            }

            if !runner.lines.isEmpty {
                Section("App battery output") {
                    ForEach(Array(runner.lines.enumerated()), id: \.offset) { _, entry in
                        Text(entry)
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                            .listRowSeparator(.hidden)
                    }
                }
            }
        }
    }

    private func row(_ harness: Harness) -> some View {
        Button {
            runSequence([harness])
        } label: {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(harness.name)
                        .foregroundStyle(.primary)
                    Text(harness.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(harness.id)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 12)
                if active == harness.id {
                    ProgressView()
                } else if let duration = elapsed[harness.id] {
                    Text(format(duration))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(active != nil)
    }

    private func runSequence(_ queue: [Harness]) {
        Task {
            for harness in queue {
                active = harness.id
                let started = ContinuousClock.now
                await harness.run()
                elapsed[harness.id] = ContinuousClock.now - started
            }
            active = nil
        }
    }

    private func harnesses(_ runner: VerificationRunner) -> [Harness] {
        [
            Harness(id: "--verify",
                    name: "App battery",
                    detail: "T6 · T12 · T21 · T22 · T23 · T29 · T30 · T34 · T35 · T37 · T69 · T79",
                    rendersInApp: true) { await runner.runAll() },
            Harness(id: "--token-audit",
                    name: "Token audit",
                    detail: "T50 · T51 · T52 — context accounting and the menu parse",
                    rendersInApp: false) { await TokenAudit.run() },
            Harness(id: "--stance-probe",
                    name: "Stance probe",
                    detail: "T26 · T28 · T31 — input trust, grounding, volume framing",
                    rendersInApp: false) { await StanceProbe.run() },
            Harness(id: "--growth-audit",
                    name: "Growth audit",
                    detail: "Per-call-site token, latency and transcript budgets",
                    rendersInApp: false) { await GrowthAudit.run() },
            Harness(id: "--schema-probe",
                    name: "Schema probe",
                    detail: "Why RoundDecision fails guided generation — variants A, B, C",
                    rendersInApp: false) { await SchemaProbe.run() },
            Harness(id: "--position-probe",
                    name: "Position probe",
                    detail: "Is the failure a function of position in the process?",
                    rendersInApp: false) { await SchemaProbe.positionProbe() },
            Harness(id: "--retry-probe",
                    name: "Retry probe",
                    detail: "Does one retry clear the decode failure?",
                    rendersInApp: false) { await SchemaProbe.retryProbe() }
        ]
    }

    private func format(_ duration: Duration) -> String {
        let total = Double(duration.components.seconds)
            + Double(duration.components.attoseconds) * 1e-18
        if total < 60 { return String(format: "%.1fs", total) }
        return String(format: "%dm %02ds", Int(total) / 60, Int(total) % 60)
    }
}

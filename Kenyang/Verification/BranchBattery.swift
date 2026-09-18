import Foundation
import FoundationModels

// TB — the 20-scenario branch-selection battery.
//
// Every previous branch measurement used ONE scenario, whose verdict is `insufficient`:
// a state where `exploit` is not clearly wrong. 71 calls said `exploit` 92% of the time,
// which established that the bias survives the decode-swallow fix and nothing more. A
// model that always says `exploit` and a model that correctly says `exploit` because the
// hypothesis keeps holding are indistinguishable on that scenario.
//
// This varies the one thing that should drive the branch — what the ratings say about
// the hypothesis — and holds everything else fixed. The number that matters is not the
// pivot rate. It is the DIFFERENCE between the pivot rate when the tools say
// `contradicted` and the pivot rate when they say `supported`.
//
//     discrimination = P(pivot | contradicted) − P(pivot | supported)
//
// At 0 the model is not reading the evidence and the guards are doing all the work,
// which is L2 with extra steps. Well above 0 and branch selection tracks the data.
//
// The move recorded is the model's RAW output, read before `ConsistencyGuard` and the
// verdict guard run. Measuring after them would measure the guards.

enum BranchBattery {

    struct Scenario {
        let id: Int
        let label: String
        let category: MenuCategory
        let expected: Rating
        let events: [TasteEvent]
        let capacity: CapacityState

        /// A reading that agrees with what the app predicted, so `checkCapacityModel`
        /// answers `consistent`.
        ///
        /// Run 1 supplied none, and the tool therefore said `insufficient — the budget
        /// is an unverified estimate` in all twenty scenarios. The model folded that
        /// constant into its move ("the hypothesis is supported, but the remaining
        /// budget is unverified, so I'll pivot"), which means run 1 varied one input and
        /// left a second one pinned to a value that argues for changing course. The
        /// point of this battery is that exactly one thing moves.
        var fullness: [FullnessReading] {
            [FullnessReading(value: CapacityEngine.predictedFullness(capacity),
                             cumulativeSatiety: capacity.spent)]
        }

        /// The same computation `RoundAgent.deterministicVerdict` performs, so the
        /// battery scores against what the app itself would conclude.
        var verdict: HypothesisVerdict {
            let p = ValueEngine.categoryPosterior(category, events: events)
            guard p.sampleCount >= ValueEngine.minimumSamples else { return .insufficient }
            return p.mean >= expected.score - 0.25 ? .supported : .contradicted
        }

        /// `nil` where either branch is defensible. Those scenarios are measured and
        /// reported, never scored — counting them would manufacture a result.
        var correctMove: RoundMove? {
            switch verdict {
            case .contradicted: .pivot
            case .supported:    .exploit
            case .insufficient: nil
            }
        }

        var claim: String {
            "The value is concentrated at the \(category.label.lowercased()) — I expect \(expected.rawValue) from it."
        }
    }

    // MARK: - The scenarios

    private static func rated(_ name: String, _ category: MenuCategory, _ ratings: [Rating]) -> [TasteEvent] {
        ratings.map {
            TasteEvent(dishName: name, category: category, rating: $0, portion: .normal, roundIndex: 1)
        }
    }

    static let scenarios: [Scenario] = {
        let healthy = CapacityState(maxSatiety: 9, spent: 3.0)
        let late    = CapacityState(maxSatiety: 9, spent: 6.2)

        var s: [Scenario] = []
        func add(_ label: String, _ category: MenuCategory, _ expected: Rating,
                 _ ratings: [Rating], _ capacity: CapacityState) {
            s.append(Scenario(id: s.count + 1, label: label, category: category,
                              expected: expected,
                              events: rated("\(category.label) plate", category, ratings),
                              capacity: capacity))
        }

        // ── CONTRADICTED ×7 — the ratings falsify the claim. Correct move: pivot.
        add("premium meat expected good, rated skip×3",   .meat,      .good, [.skip, .skip, .skip],  healthy)
        add("raw bar expected good, rated skip×2",        .raw,       .good, [.skip, .skip],         healthy)
        add("fried expected good, rated fine/skip",       .fried,     .good, [.fine, .skip],         healthy)
        add("dessert expected fine, rated skip×3",        .dessert,   .fine, [.skip, .skip, .skip],  healthy)
        add("vegetable expected good, rated skip/fine",   .vegetable, .good, [.skip, .fine],         healthy)
        add("soup expected fine, rated skip×2",           .soup,      .fine, [.skip, .skip],         late)
        add("starch expected good, rated skip×4",         .starch,    .good, [.skip, .skip, .skip, .skip], late)

        // ── SUPPORTED ×7 — the ratings bear the claim out. Correct move: exploit.
        add("meat expected good, rated good×3",           .meat,      .good, [.good, .good, .good],  healthy)
        add("raw expected fine, rated good×2",            .raw,       .fine, [.good, .good],         healthy)
        add("raw expected good, rated good/good/fine",    .raw,       .good, [.good, .good, .fine],  healthy)
        add("vegetable expected fine, rated fine×2",      .vegetable, .fine, [.fine, .fine],         healthy)
        add("fried expected fine, rated good/fine",       .fried,     .fine, [.good, .fine],         healthy)
        add("dessert expected fine, rated good×2",        .dessert,   .fine, [.good, .good],         late)
        add("meat expected fine, rated good×4",           .meat,      .fine, [.good, .good, .good, .good], late)

        // ── INSUFFICIENT ×6 — below minimum n. Measured, never scored. This is the
        //    state every previous branch measurement used, kept here so the old number
        //    is directly comparable to the new ones.
        add("meat expected good, one rating only",        .meat,      .good, [.good],                healthy)
        add("raw expected good, one rating only",         .raw,       .good, [.skip],                healthy)
        add("fried expected fine, nothing rated",         .fried,     .fine, [],                     healthy)
        add("dessert expected good, nothing rated",       .dessert,   .good, [],                     healthy)
        add("soup expected good, one rating only",        .soup,      .good, [.fine],                late)
        add("starch expected fine, nothing rated",        .starch,    .fine, [],                     late)

        return s
    }()

    // MARK: - The run

    static func run() async {
        line(rule("=", 76))
        line("BRANCH BATTERY (TB) — does the move track the evidence, or collapse?")
        line("\(scenarios.count) scenarios · raw model move, read BEFORE the guards")
        line("tier: \(AgentCapabilities.summary)")
        line(rule("=", 76))

        guard case .available = SystemLanguageModel.default.availability else {
            line("model unavailable — halted. Nothing below is a result about the app.")
            return
        }

        var moves: [HypothesisVerdict: [RoundMove: Int]] = [:]
        var decodeFailures = 0
        var excluded = 0
        var correct = 0
        var scored = 0
        var guardWouldOverride = 0

        for scenario in scenarios {
            await ToolContext.shared.resetInvocations()
            await ToolContext.shared.load(sightings: spread(),
                                          events: scenario.events,
                                          capacity: scenario.capacity,
                                          minutesRemaining: 40,
                                          exclusions: [],
                                          basisRecords: [],
                                          fullnessReadings: scenario.fullness,
                                          hypothesisCategory: scenario.category)

            // The shipping call site, reproduced exactly — same instructions, same
            // tools, same options, same prompt shape as `RoundAgent.decide`.
            let session = AgentCapabilities.session(tools: AgentToolbox.readTools,
                                                    instructions: RoundAgent.instructions)
            let prompt = """
                Your hypothesis was: \(scenario.claim)
                Call evaluateHypothesis for the \(scenario.category.rawValue), \
                getRemainingCapacity, and checkCapacityModel to see whether the \
                remaining budget can still be trusted. Then decide.
                """

            do {
                let decision = try await session.respond(to: prompt,
                                                         generating: RoundDecision.self,
                                                         options: AgentCapabilities.toolBound(250)).content
                let move = decision.move
                moves[scenario.verdict, default: [:]][move, default: 0] += 1

                var mark = "  "
                if let expected = scenario.correctMove {
                    scored += 1
                    if move == expected { correct += 1; mark = "✅" } else { mark = "❌" }
                }
                if !ConsistencyGuard.agrees(reason: decision.because, move: move) {
                    guardWouldOverride += 1
                }
                let invoked = await ToolContext.shared.invocationList
                line("\(mark) \(pad(scenario.id)) [\(scenario.verdict.rawValue.prefix(7))] \(move.rawValue.padding(toLength: 7, withPad: " ", startingAt: 0)) \(scenario.label)")
                line("        tools: \(invoked.isEmpty ? "NONE" : invoked.joined(separator: ", "))")
                line("        because: \(decision.because.prefix(96))")
            } catch {
                if "\(error)".contains("decodingFailure") {
                    decodeFailures += 1
                    line("   \(pad(scenario.id)) [\(scenario.verdict.rawValue.prefix(7))] DECODE-FAIL  \(scenario.label)")
                } else {
                    excluded += 1
                    line("   \(pad(scenario.id)) [\(scenario.verdict.rawValue.prefix(7))] EXCLUDED \(String("\(error)".prefix(60)))")
                }
            }
        }

        report(moves: moves, correct: correct, scored: scored,
               decodeFailures: decodeFailures, excluded: excluded,
               guardWouldOverride: guardWouldOverride)
    }

    // MARK: - The result

    private static func report(moves: [HypothesisVerdict: [RoundMove: Int]],
                               correct: Int,
                               scored: Int,
                               decodeFailures: Int,
                               excluded: Int,
                               guardWouldOverride: Int) {
        line("")
        line(rule("=", 76))
        line("MOVE DISTRIBUTION BY VERDICT")
        line(rule("─", 76))
        line("  verdict         n   exploit   pivot    pivot rate")
        for verdict in [HypothesisVerdict.contradicted, .supported, .insufficient] {
            let row = moves[verdict] ?? [:]
            let exploit = row[.exploit] ?? 0
            let pivot = row[.pivot] ?? 0
            let n = exploit + pivot
            let rate = n > 0 ? "\(Int((Double(pivot) / Double(n)) * 100))%" : "n/a"
            line("  \(verdict.rawValue.padding(toLength: 14, withPad: " ", startingAt: 0)) \(pad(n))   \(pad(exploit))        \(pad(pivot))       \(rate)")
        }

        let contradicted = moves[.contradicted] ?? [:]
        let supported = moves[.supported] ?? [:]
        let cN = (contradicted[.exploit] ?? 0) + (contradicted[.pivot] ?? 0)
        let sN = (supported[.exploit] ?? 0) + (supported[.pivot] ?? 0)

        line("")
        line(rule("─", 76))
        guard cN >= 3 && sN >= 3 else {
            line("INCONCLUSIVE — \(cN) contradicted and \(sN) supported scenarios decoded.")
            line("Fewer than 3 either side cannot separate discrimination from noise.")
            line("Decode failures \(decodeFailures), excluded \(excluded).")
            line(rule("=", 76))
            return
        }

        let pivotGivenContradicted = Double(contradicted[.pivot] ?? 0) / Double(cN)
        let pivotGivenSupported = Double(supported[.pivot] ?? 0) / Double(sN)
        let discrimination = pivotGivenContradicted - pivotGivenSupported

        line("DISCRIMINATION")
        line("  P(pivot | contradicted) = \(pct(pivotGivenContradicted))")
        line("  P(pivot | supported)    = \(pct(pivotGivenSupported))")
        line("  difference              = \(pct(discrimination))")
        line("")

        // The bar is set here rather than after the fact, so the result cannot be read
        // to suit whatever came out.
        if discrimination >= 0.5 {
            line("  → BRANCH SELECTION TRACKS THE EVIDENCE.")
            line("    The move follows the verdict rather than the prior. The agency")
            line("    claim rests on this and it is the model's own behaviour.")
        } else if discrimination >= 0.2 {
            line("  → PARTIAL. The move leans the right way and is not reliable.")
            line("    The guards remain load-bearing; claim exactly that and no more.")
        } else {
            line("  → MODE COLLAPSE. The move does not read the evidence.")
            line("    Whatever the tools say, the answer is the same. `ConsistencyGuard`")
            line("    and the verdict guard are producing the correct behaviour, not the")
            line("    model — which is L2, and must be reported as L2.")
        }

        line("")
        line("  scored \(correct)/\(scored) correct on scenarios with a right answer")
        line("  insufficient scenarios are measured, never scored — either branch is defensible")
        line("  ConsistencyGuard would have overridden \(guardWouldOverride) decoded answer(s)")
        if decodeFailures > 0 || excluded > 0 {
            line("  decode failures \(decodeFailures) · excluded \(excluded) of \(scenarios.count)")
        }
        line(rule("=", 76))
    }

    // MARK: -

    /// Capacity exhaustion never reaches the model: `StopGuard` fires first. Asserted
    /// here so the battery covers the branch rather than quietly omitting it.
    static func stopIsDeterministic() {
        line("")
        line(rule("─", 76))
        line("STOP is not a branch the model gets to choose")
        let exhausted = CapacityState(maxSatiety: 9, spent: 8.5)
        let reason = StopGuard.reason(capacity: exhausted, minutesRemaining: 40)
        let clock = StopGuard.reason(capacity: CapacityState(maxSatiety: 9, spent: 1),
                                     minutesRemaining: 0)
        line("  capacity 94% spent      → \(reason.rawValue)")
        line("  seating time expired    → \(clock.rawValue)")
        line("  Across the day-3 spike the model chose stop 0/3 times when handed")
        line("  exhausted capacity. It is computed, not asked — see StopGuard.")
        line(rule("─", 76))
    }

    private static func spread() -> [DishSighting] {
        DemoSpread.standard.map {
            DishSighting(name: $0.name, category: $0.category,
                         printedCategory: $0.printed, tierRank: $0.tier)
        }
    }

    private static func pct(_ d: Double) -> String { "\(Int((d * 100).rounded()))%" }
    private static func pad(_ i: Int) -> String { i < 10 ? " \(i)" : "\(i)" }
    private static func rule(_ c: String, _ n: Int) -> String { String(repeating: c, count: n) }
    private static func line(_ s: String) { print("[TB] \(s)"); fflush(stdout) }
}

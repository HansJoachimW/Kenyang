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

        t30_exclusionValidator()
        t29_minimumSamples()
        t37_counterfactual()
        await t21_t22_toolCoverage()
        await t35_hypothesisDeath()
        await t34_pathVariance()
        await t4_contextHeadroom()

        emit("")
        emit("=== VERIFICATION COMPLETE ===")
        running = false
    }

    private func t30_exclusionValidator() {
        emit("──── T30 ⭐ exclusion validator, ternary ────")

        let known = DishSighting(name: "Prawn cocktail", station: .rawBar,
                                 ingredientsKnown: true, ingredients: ["prawn", "mayonnaise"])
        let clean = DishSighting(name: "Green salad", station: .salad,
                                 ingredientsKnown: true, ingredients: ["lettuce", "tomato"])
        let opaque = DishSighting(name: "Nasi Goreng", station: .riceAndNoodles,
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
        let one = [TasteEvent(dishName: "Sashimi", station: .rawBar, rating: .good, portion: .normal, roundIndex: 1)]
        let two = one + [TasteEvent(dishName: "Sashimi", station: .rawBar, rating: .good, portion: .normal, roundIndex: 1)]

        let p1 = ValueEngine.posterior(dishName: "Sashimi", station: .rawBar, events: one)
        let p2 = ValueEngine.posterior(dishName: "Sashimi", station: .rawBar, events: two)

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
            DishSighting(name: $0.name, station: $0.station,
                         isRationed: $0.rationed, isMadeToOrder: $0.madeToOrder)
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
            DishSighting(name: $0.name, station: $0.station,
                         isRationed: $0.rationed, isMadeToOrder: $0.madeToOrder)
        }

        await ToolContext.shared.resetInvocations()
        await ToolContext.shared.load(sightings: spread, events: [],
                                      capacity: CapacityState(maxSatiety: 9, spent: 0),
                                      minutesRemaining: 55, exclusions: ["peanut"],
                                      basisRecords: [], fullnessReadings: [], hypothesisStation: .rawBar)

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
            ("evaluateHypothesis", try? await EvaluateHypothesisTool().call(arguments: .init(station: .rawBar, expectedRating: .good))),
            ("getPosterior",       try? await GetPosteriorTool().call(arguments: .init(station: .grill))),
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
            DishSighting(name: $0.name, station: $0.station,
                         isRationed: $0.rationed, isMadeToOrder: $0.madeToOrder)
        }
        let badRawBar = [
            TasteEvent(dishName: "Sashimi", station: .rawBar, rating: .skip, portion: .taste, roundIndex: 1),
            TasteEvent(dishName: "Oysters", station: .rawBar, rating: .skip, portion: .taste, roundIndex: 1),
            TasteEvent(dishName: "Prawns", station: .rawBar, rating: .skip, portion: .taste, roundIndex: 1)
        ]
        let hypothesis = ValueHypothesis(claim: "The value is concentrated at the raw bar.",
                                         station: .rawBar, basis: .scarcity,
                                         confidence: .high, expectedRating: .good)

        let posterior = ValueEngine.stationPosterior(.rawBar, events: badRawBar)
        let verdict: HypothesisVerdict = posterior.sampleCount < ValueEngine.minimumSamples
            ? .insufficient
            : (posterior.mean >= hypothesis.expectedRating.score - 0.25 ? .supported : .contradicted)

        emit("rated the hypothesised station skip×3 → observed \(String(format: "%.2f", posterior.mean)), expected \(String(format: "%.2f", hypothesis.expectedRating.score))")
        emit("\(verdict == .contradicted ? "✅" : "❌") deterministic verdict: \(verdict.rawValue)")

        let trace = TraceLog()
        let agent = RoundAgent(trace: trace)
        let input = AgentInput(sightings: spread, events: badRawBar,
                               capacity: CapacityState(maxSatiety: 9, spent: 2.1),
                               minutesRemaining: 45, exclusions: [], basisRecords: [],
                               roundIndex: 2, currentHypothesis: hypothesis)
        let outcome = await agent.run(input)

        if case .planned(_, let newHypothesis, _) = outcome {
            let pivoted = newHypothesis.station != hypothesis.station
            emit("\(pivoted ? "✅" : "❌") pivoted: \(hypothesis.station.rawValue) → \(newHypothesis.station.rawValue)")
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
            DishSighting(name: $0.name, station: $0.station,
                         isRationed: $0.rationed, isMadeToOrder: $0.madeToOrder)
        }
        let thin = Array(spread.prefix(6)).map {
            DishSighting(name: $0.name, station: $0.station)
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

    private func t4_contextHeadroom() async {
        emit("──── T4 ⭐ context headroom, realistic prose ────")
        guard case .available = SystemLanguageModel.default.availability else {
            emit("⚠️ model unavailable — skipped"); emit(""); return
        }

        let stations = ["raw bar with sashimi, oysters and chilled prawns",
                        "a grill serving lamb chops, sirloin and chicken skewers",
                        "a fried station with tempura, spring rolls and karaage",
                        "rice and noodle counters", "a salad bar", "clear and miso soups",
                        "a dessert counter with cakes, fruit and ice cream"]

        let cases: [(String, Int)] = [(("typical"), 1), ("large", 4), ("extreme", 12)]
        for (label, repeats) in cases {
            let body = Array(repeating: stations.joined(separator: ", "), count: repeats)
                .joined(separator: ". The far side of the room also has ")
            let prompt = "The buffet offers \(body). Capacity remaining is about three plates. Where is the value concentrated?"
            let approx = prompt.count / 4
            do {
                _ = try await LanguageModelSession(instructions: RoundAgent.instructions)
                    .respond(to: prompt, generating: ValueHypothesis.self).content
                emit("✅ \(label): ~\(approx) tokens (\(prompt.count) chars) — OK")
            } catch {
                let text = "\(error)"
                let kind = text.contains("exceededContextWindow") ? "CONTEXT OVERFLOW"
                    : text.contains("guardrail") ? "GUARDRAIL"
                    : String(text.prefix(50))
                emit("💥 \(label): ~\(approx) tokens (\(prompt.count) chars) — \(kind)")
            }
        }
        emit("→ the app's worst-case prompt must sit under 4,096 by construction")
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
                    detail: "T4 · T21 · T22 · T29 · T30 · T34 · T35 · T37",
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

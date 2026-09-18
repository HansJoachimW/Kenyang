import SwiftUI

private struct Harness: Identifiable {
    let id: String
    let name: String
    let detail: String
    let rendersInApp: Bool
    let run: @MainActor () async -> Void
}

struct VerificationView: View {
    @Environment(\.kenyangStore) private var store
    /// The live session's trace, so a harness can put a guard override into the panel
    /// the diner actually looks at.
    var trace: TraceLog?
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
                    detail: "10 checks — capture, entities, guardrails, tools, agent paths",
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
                    rendersInApp: false) { await SchemaProbe.retryProbe() },
            Harness(id: "seed-tier-2",
                    name: "Seed tier history — 2 visits",
                    detail: "Screen 2's refusal state. Below three visits it will not argue",
                    rendersInApp: false) {
                        TierFixtures.clear(runner.store)
                        TierFixtures.seed(into: runner.store, visits: 2)
                        print("[SEED] Gyu-Kaku Kemang · 2 visits — expect the refusal")
                    },
            Harness(id: "seed-tier-6",
                    name: "Seed tier history — 6 visits",
                    detail: "Screen 2's confident state, with a premium rung that never earned it",
                    rendersInApp: false) {
                        TierFixtures.clear(runner.store)
                        TierFixtures.seed(into: runner.store, visits: 6)
                        print("[SEED] Gyu-Kaku Kemang · 6 visits — expect Go Standard")
                    },
            Harness(id: "seed-override",
                    name: "Seed a guard override",
                    detail: "Screen 7B — the consistency guard rejecting the model, in the live trace",
                    rendersInApp: false) {
                        guard let trace else {
                            print("[SEED] no live trace — open this from a session")
                            return
                        }
                        trace.record(kind: .verdict, title: "Verdict: contradicted",
                                     detail: "evaluateHypothesis(raw) = contradicted (observed 0.00 vs expected 1.00, n=3)",
                                     deterministic: true)
                        trace.record(
                            kind: .guardrail,
                            title: "Consistency guard overrode the model",
                            detail: "Reason said the hypothesis was contradicted but the move was exploit — overridden",
                            deterministic: true,
                            override: GuardOverride(
                                wrote: "The tools say the hypothesis is CONTRADICTED, and the budget estimate is unreliable.",
                                chose: "exploit",
                                forced: "pivot",
                                guardName: "ConsistencyGuard",
                                layer: 6,
                                did: "The stated reason disagreed with the chosen move, so the move was rejected and the pivot forced."))
                        trace.record(kind: .decision, title: "Pivot forced",
                                     detail: "raw → meat, on the tool's authority",
                                     deterministic: true)
                        print("[SEED] guard override in the trace — open Trace to see it")
                    },
            Harness(id: "--branch-battery",
                    name: "Branch battery (TB)",
                    detail: "20 scenarios — does the move track the verdict, or collapse?",
                    rendersInApp: false) {
                        BranchBattery.stopIsDeterministic()
                        await BranchBattery.run()
                    }
        ]
    }

    private func format(_ duration: Duration) -> String {
        let total = Double(duration.components.seconds)
            + Double(duration.components.attoseconds) * 1e-18
        if total < 60 { return String(format: "%.1fs", total) }
        return String(format: "%dm %02ds", Int(total) / 60, Int(total) % 60)
    }
}

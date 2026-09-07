import Foundation
import FoundationModels

enum GrowthAudit {

    struct Budget {
        let site: String
        let maxTokens: Int
        let maxSeconds: Double
        let maxTranscriptEntries: Int
    }

    static let budgets = [
        Budget(site: "hypothesise", maxTokens: 2200, maxSeconds: 35, maxTranscriptEntries: 36),
        Budget(site: "setIntent",   maxTokens: 800,  maxSeconds: 5,  maxTranscriptEntries: 6),
        Budget(site: "decide",      maxTokens: 1600, maxSeconds: 10, maxTranscriptEntries: 12)
    ]

    static func run() async {
        line(rule("=", 72))
        line("GROWTH AUDIT — T73 multi-round context growth · T74 regression budget")
        line(rule("=", 72))

        let model = SystemLanguageModel.default
        guard model.availability == .available else {
            line("model unavailable — cannot run")
            return
        }

        await t73(model)
        await t74(model)

        line("")
        line(rule("=", 72))
        line("GROWTH AUDIT COMPLETE")
        line(rule("=", 72))
    }

    private static func t73(_ model: SystemLanguageModel) async {
        line("")
        line(rule("─", 72))
        line("T73 — MULTI-ROUND CONTEXT GROWTH")
        line("Every context number so far was ROUND 1. A real meal is 4–6 rounds and")
        line("each one replays MORE rated dishes into the prompt. This measures the")
        line("slope, which is what decides whether a long meal survives the window.")
        line(rule("─", 72))
        line("")

        let dishes = ["Karubi", "Harami", "Sashimi moriawase", "Prawns", "Gyu tan",
                      "Fried rice", "Miso soup", "Green salad", "Toro", "Wagyu rib"]
        var measurements: [(round: Int, rated: Int, tokens: Int)] = []

        for round in 1...6 {
            let rated = min((round - 1) * 2, dishes.count)
            let history = (0..<rated).map { i in
                "- \(dishes[i]): rated \(i % 3 == 0 ? "good" : (i % 3 == 1 ? "fine" : "skip")), 1.0 satiety"
            }.joined(separator: "\n")

            let prompt = """
                Round \(round). The diner has eaten and rated these already:
                \(history.isEmpty ? "- nothing yet" : history)
                The tools say the hypothesis is contradicted and the budget estimate \
                is unreliable. Choose the next move and say why.
                """

            let promptTokens = await count { try await model.tokenCount(for: Prompt(prompt)) }
            let schemaTokens = await count { try await model.tokenCount(for: RoundDecision.generationSchema) }
            let instr = await count { try await model.tokenCount(for: Instructions(RoundAgent.instructions)) }
            let tools = await count { try await model.tokenCount(for: AgentToolbox.readTools) }

            guard let p = promptTokens, let s = schemaTokens, let i = instr, let t = tools else {
                line("  round \(round): token count unavailable")
                continue
            }
            let total = p + s + i + t
            measurements.append((round, rated, total))
            let bar = String(repeating: "█", count: max(1, total / 60))
            line("  round \(round)  \(pad(rated))  rated  →  \(pad4(total)) tok  \(pct(total, 4096))%  \(bar)")
        }

        guard let first = measurements.first, let last = measurements.last, measurements.count > 1 else {
            line("  insufficient measurements")
            return
        }

        let deltaTokens = last.tokens - first.tokens
        let deltaRated = max(1, last.rated - first.rated)
        let perDish = Double(deltaTokens) / Double(deltaRated)

        line("")
        line("  growth: \(deltaTokens) tokens over \(deltaRated) rated dishes")
        line("  → \(String(format: "%.1f", perDish)) tokens per additional rated dish")

        let headroom = 4096 - last.tokens
        let moreDishes = perDish > 0 ? Int(Double(headroom) / perDish) : 9999
        line("  → headroom after round 6: \(headroom) tokens ≈ \(moreDishes) more rated dishes")

        let verdict = last.tokens < 3000
        line("")
        line("  T73: \(verdict ? "PASS" : "FAIL") — round 6 sits at \(last.tokens) of 4096 (\(pct(last.tokens, 4096))%)")
        if verdict && moreDishes < 20 {
            line("  ⚠️ passes, but the slope is real. A 20-dish meal would not fit.")
        }
    }

    private static func t74(_ model: SystemLanguageModel) async {
        line("")
        line(rule("─", 72))
        line("T74 — REGRESSION BUDGET")
        line("hypothesise grew 45% in latency and 15% in tokens between 2026-09-04")
        line("and 2026-09-06 with nobody intending it, and nothing caught it. These")
        line("are ceilings. Exceeding one is a FAILURE, not a note.")
        line(rule("─", 72))
        line("")

        for b in budgets {
            line("  \(b.site.padding(toLength: 14, withPad: " ", startingAt: 0)) ≤ \(b.maxTokens) tok · ≤ \(Int(b.maxSeconds)) s · ≤ \(b.maxTranscriptEntries) entries")
        }
        line("")
        line("  Compare against the CONTEXT AUDIT numbers printed above in this")
        line("  same run — T51 measures all three sites with real calls, so this")
        line("  section states the ceiling and the audit supplies the reading.")
        line("")

        line(rule("─", 72))
        line("T74b — @Generable TYPE-NAME LEAKAGE")
        line(rule("─", 72))
        line("")
        line("  5 failures on 2026-09-06 began `DecisionB{\"because\":` — the type's")
        line("  own name leaked into the generated text and broke the JSON.")
        line("  Guard: no schema type name may appear in a decoded output string.")
        line("")

        let banned = ["RoundDecision", "ValueHypothesis", "RoundIntent", "DecisionB", "DecisionC"]
        let session = LanguageModelSession(instructions: RoundAgent.instructions)
        var clean = 0
        var attempts = 0

        for i in 1...6 {
            attempts += 1
            do {
                let d = try await session.respond(to: Fixtures.decidePrompt(),
                                                  generating: RoundDecision.self).content
                let leaked = banned.filter { d.because.contains($0) }
                if leaked.isEmpty {
                    clean += 1
                    line("  \(i): ✅ clean — \(d.move)")
                } else {
                    line("  \(i): ❌ LEAKED \(leaked.joined(separator: ", "))")
                }
            } catch {
                line("  \(i): ⛔️ decode failure (expected ~20% — T19)")
            }
        }

        line("")
        line("  clean decodes: \(clean)/\(attempts) attempted")
        line("  T74b: \(clean > 0 ? "PASS on the decoded outputs" : "INCONCLUSIVE — nothing decoded")")
    }

    private static func count(_ body: () async throws -> Int) async -> Int? {
        do { return try await body() } catch { return nil }
    }

    private static func pct(_ n: Int, _ d: Int) -> Int { Int((Double(n) / Double(d)) * 100) }
    private static func pad(_ i: Int) -> String { i < 10 ? " \(i)" : "\(i)" }
    private static func pad4(_ i: Int) -> String { String(repeating: " ", count: max(0, 4 - "\(i)".count)) + "\(i)" }
    private static func rule(_ c: String, _ n: Int) -> String { String(repeating: c, count: n) }
    private static func line(_ s: String) { print("[GROWTH] \(s)"); fflush(stdout) }
}

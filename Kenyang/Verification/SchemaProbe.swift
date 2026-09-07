import Foundation
import FoundationModels

// Follow-up to the T52 finding: RoundDecision failed guided generation 6/8 times,
// while ValueHypothesis and RoundIntent succeeded every time in the same run.
//
// Hypothesis: RoundDecision's @Guide text is written as CONVERSATIONAL INSTRUCTIONS
// ("First, state what the tool results actually say." / "Now choose, consistent with
// what you just wrote:"). That phrasing invites a prose answer, and the failures are
// all prose — correct reasoning, unparseable shape.
//
// This A/B tests that hypothesis. Same fields, same order, same semantics.
// Only the guide WORDING changes.

enum SchemaProbe {

    static let attempts = 12

    /// Isolates ONE variable: position in the process. Identical type, prompt,
    /// tools and instructions, three blocks back to back. If the failure rate
    /// climbs with position, the cause is accumulated process/session state, not
    /// the type. If it stays flat, the T52 result was run-to-run variance.
    static func positionProbe() async {
        line(rule("=", 72))
        line("POSITION PROBE — is RoundDecision failure a function of position?")
        line("3 blocks x \(attempts) identical RoundDecision calls, one process")
        line(rule("=", 72))

        guard case .available = SystemLanguageModel.default.availability else {
            line("model unavailable — halted"); return
        }

        var rates: [Int] = []
        for block in 1...3 {
            var ok = 0
            var moves: [String: Int] = [:]
            line("")
            line(rule("─", 72))
            line("BLOCK \(block) — calls \((block - 1) * attempts + 1)–\(block * attempts) of \(attempts * 3)")
            line(rule("─", 72))
            for i in 1...attempts {
                do {
                    let s = LanguageModelSession(tools: AgentToolbox.readTools,
                                                 instructions: RoundAgent.instructions)
                    let r = try await s.respond(to: Fixtures.decidePrompt(),
                                                generating: RoundDecision.self)
                    ok += 1
                    moves[r.content.move.rawValue, default: 0] += 1
                    line("  \(pad(i)): OK   \(r.content.move.rawValue)")
                } catch {
                    line("  \(pad(i)): FAIL \(short(error))")
                }
            }
            let rate = Int((Double(ok) / Double(attempts)) * 100)
            rates.append(rate)
            line("  → block \(block): \(ok)/\(attempts) (\(rate)%)   \(moves.map { "\($0.key)×\($0.value)" }.sorted().joined(separator: " "))")
        }

        line("")
        line(rule("=", 72))
        line("RATES BY POSITION: \(rates.map { "\($0)%" }.joined(separator: "  →  "))")
        let spread = (rates.max() ?? 0) - (rates.min() ?? 0)
        line(spread >= 30
             ? "→ POSITION-DEPENDENT. Accumulated process state is implicated."
             : "→ FLAT. The T52 result was run-to-run variance, not position.")
        line(rule("=", 72))
    }

    /// Post-fix verification: does one retry actually clear the ~20%?
    /// Mirrors RoundAgent.retrying() exactly — same predicate, same single retry.
    static func retryProbe() async {
        line(rule("=", 72))
        line("RETRY PROBE — does one retry clear the RoundDecision decode failure?")
        line("\(attempts * 3) RoundDecision calls, retried once on decodingFailure")
        line(rule("=", 72))

        guard case .available = SystemLanguageModel.default.availability else {
            line("model unavailable — halted"); return
        }

        var firstTry = 0, afterRetry = 0, hardFail = 0
        var moves: [String: Int] = [:]

        for i in 1...(attempts * 3) {
            func once() async throws -> RoundDecision {
                let s = LanguageModelSession(tools: AgentToolbox.readTools,
                                             instructions: RoundAgent.instructions)
                return try await s.respond(to: Fixtures.decidePrompt(),
                                           generating: RoundDecision.self).content
            }
            do {
                let r = try await once()
                firstTry += 1
                moves[r.move.rawValue, default: 0] += 1
                line("  \(pad(i)): OK          \(r.move.rawValue)")
            } catch {
                let transient = "\(error)".contains("decodingFailure")
                    || "\(error)".contains("guardrailViolation")
                guard transient else {
                    hardFail += 1
                    line("  \(pad(i)): HARD FAIL  \(short(error))")
                    continue
                }
                do {
                    let r = try await once()
                    afterRetry += 1
                    moves[r.move.rawValue, default: 0] += 1
                    line("  \(pad(i)): OK ON RETRY \(r.move.rawValue)")
                } catch {
                    hardFail += 1
                    line("  \(pad(i)): FAILED TWICE \(short(error))")
                }
            }
        }

        let n = attempts * 3
        let ok = firstTry + afterRetry
        line("")
        line(rule("=", 72))
        line("  first attempt succeeded : \(firstTry)/\(n) (\(Int(Double(firstTry) / Double(n) * 100))%)")
        line("  rescued by the retry    : \(afterRetry)")
        line("  failed twice            : \(hardFail)")
        line("  EFFECTIVE FAILURE RATE  : \(Int(Double(hardFail) / Double(n) * 100))%  (was ~20%)")
        line("  moves: \(moves.map { "\($0.key)×\($0.value)" }.sorted().joined(separator: " "))")
        line(rule("=", 72))
    }

    static func run() async {
        line(rule("=", 72))
        line("SCHEMA PROBE — why does RoundDecision fail guided generation?")
        line("\(attempts) attempts per variant, identical prompt and tools")
        line(rule("=", 72))

        guard case .available = SystemLanguageModel.default.availability else {
            line("model unavailable — halted")
            return
        }

        await trial("A · CURRENT (instructional guides)") {
            let s = LanguageModelSession(tools: AgentToolbox.readTools,
                                         instructions: RoundAgent.instructions)
            let r = try await s.respond(to: Fixtures.decidePrompt(), generating: RoundDecision.self)
            return "\(r.content.move.rawValue) — \(r.content.because.prefix(60))"
        }

        await trial("B · DECLARATIVE (nouns, not commands)") {
            let s = LanguageModelSession(tools: AgentToolbox.readTools,
                                         instructions: RoundAgent.instructions)
            let r = try await s.respond(to: Fixtures.decidePrompt(), generating: DecisionB.self)
            return "\(r.content.move.rawValue) — \(r.content.because.prefix(60))"
        }

        await trial("C · DECLARATIVE + no ordering language") {
            let s = LanguageModelSession(tools: AgentToolbox.readTools,
                                         instructions: RoundAgent.instructions)
            let r = try await s.respond(to: Fixtures.decidePrompt(), generating: DecisionC.self)
            return "\(r.content.move.rawValue) — \(r.content.because.prefix(60))"
        }

        line("")
        line(rule("=", 72))
        line("PROBE COMPLETE")
        line(rule("=", 72))
    }

    private static func trial(_ name: String, _ body: @escaping () async throws -> String) async {
        line("")
        line(rule("─", 72))
        line(name)
        line(rule("─", 72))

        var ok = 0
        var moves: [String: Int] = [:]
        for i in 1...attempts {
            do {
                let summary = try await body()
                ok += 1
                let move = summary.split(separator: " ").first.map(String.init) ?? "?"
                moves[move, default: 0] += 1
                line("  \(pad(i)): OK   \(summary)")
            } catch {
                line("  \(pad(i)): FAIL \(short(error))")
            }
        }
        let rate = Int((Double(ok) / Double(attempts)) * 100)
        line("")
        line("  → \(ok)/\(attempts) parsed (\(rate)%)   moves: \(moves.map { "\($0.key)×\($0.value)" }.sorted().joined(separator: " "))")
    }

    private static func pad(_ i: Int) -> String { i < 10 ? " \(i)" : "\(i)" }

    private static func short(_ error: Error) -> String {
        let t = "\(error)"
        if t.contains("decodingFailure") {
            if let r = t.range(of: "Text: ") {
                let after = t[r.upperBound...]
                let snippet = after.prefix(70).replacingOccurrences(of: "\n", with: " ⏎ ")
                return "decodingFailure — model wrote prose: \"\(snippet)…\""
            }
            return "decodingFailure"
        }
        if t.contains("guardrailViolation") { return "guardrailViolation" }
        if t.contains("exceededContextWindowSize") { return "exceededContextWindowSize" }
        return String(t.prefix(90))
    }

    private static func rule(_ c: String, _ n: Int) -> String { String(repeating: c, count: n) }
    private static func line(_ s: String) { print("[PROBE] \(s)"); fflush(stdout) }
}

// MARK: - Variants. Same fields, same order, same meaning. Only guide wording differs.

/// Guides describe WHAT THE FIELD CONTAINS, rather than telling the model what to do.
@Generable
struct DecisionB: Sendable {
    @Guide(description: "One sentence stating what the tool results say.")
    var because: String

    @Guide(description: """
        The move implied by those tool results. \
        pivot — the tools say the hypothesis is contradicted; the value is at a \
        different station. \
        exploit — the tools say the hypothesis is supported; spend remaining \
        capacity on those winners.
        """)
    var move: RoundMove
}

/// As B, with every trace of sequencing language removed ("first", "now", "then",
/// "consistent with what you just wrote") — the ordering is already enforced by
/// field order in the schema, so saying it in prose is redundant and prose-inviting.
@Generable
struct DecisionC: Sendable {
    @Guide(description: "What the tool results say, in one sentence.")
    var because: String

    @Guide(description: "pivot when the hypothesis is contradicted. exploit when it is supported.")
    var move: RoundMove
}

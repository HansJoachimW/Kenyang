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
    static let minimumScorablePerBlock = 6
    static let minimumScorableForRetry = 12

    /// Isolates ONE variable: position in the process. Identical type, prompt,
    /// tools and instructions, three blocks back to back.
    ///
    /// The question is specifically about DECODE failure, so a call that fails
    /// for an unrelated reason is not evidence either way and is excluded from
    /// the rate rather than counted against it. A block needs enough scorable
    /// attempts to have a rate at all, and a run in which nothing decoded — or
    /// everything did — is INCONCLUSIVE, because a flat line at 0% or 100% is
    /// forced by the denominator and says nothing about position.
    static func positionProbe() async {
        line(rule("=", 72))
        line("POSITION PROBE — is RoundDecision failure a function of position?")
        line("3 blocks x \(attempts) identical RoundDecision calls, one process")
        line(rule("=", 72))

        guard case .available = SystemLanguageModel.default.availability else {
            line("model unavailable — halted"); return
        }

        var rates: [Int?] = []
        var totalOK = 0
        var totalScorable = 0
        var excluded = 0
        var excludedReasons: Set<String> = []

        for block in 1...3 {
            var ok = 0
            var decodeFailures = 0
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
                    if isDecodeFailure(error) {
                        decodeFailures += 1
                        line("  \(pad(i)): FAIL \(short(error))")
                    } else {
                        excluded += 1
                        excludedReasons.insert(short(error))
                        line("  \(pad(i)): EXCLUDED (not a decode outcome) \(short(error))")
                    }
                }
            }

            let scorable = ok + decodeFailures
            totalOK += ok
            totalScorable += scorable

            if scorable >= minimumScorablePerBlock {
                let rate = Int((Double(ok) / Double(scorable)) * 100)
                rates.append(rate)
                line("  → block \(block): \(ok)/\(scorable) scorable (\(rate)%)   "
                     + "\(moves.map { "\($0.key)×\($0.value)" }.sorted().joined(separator: " "))")
            } else {
                rates.append(nil)
                line("  → block \(block): only \(scorable) scorable attempt(s) — no rate")
            }
        }

        line("")
        line(rule("=", 72))
        line("RATES BY POSITION: "
             + rates.map { $0.map { "\($0)%" } ?? "n/a" }.joined(separator: "  →  "))
        line("  scorable attempts: \(totalScorable) of \(attempts * 3)")

        if excluded > 0 {
            line("  ⚠️  \(excluded) call(s) EXCLUDED — failed for reasons unrelated to decoding:")
            for reason in excludedReasons.sorted() { line("     \(reason)") }
        }

        let known = rates.compactMap { $0 }
        if known.count < 3 {
            line("→ INCONCLUSIVE — \(3 - known.count) block(s) had fewer than "
                 + "\(minimumScorablePerBlock) scorable attempts. Fix the upstream failure first.")
        } else if totalOK == 0 {
            line("→ INCONCLUSIVE — nothing decoded in any block. A flat 0% is forced by the")
            line("  denominator, not observed; it is not evidence that position is irrelevant.")
        } else if totalOK == totalScorable {
            line("→ INCONCLUSIVE — everything decoded, so there is no failure to attribute")
            line("  to position. Re-run when the decode failure is reproducing.")
        } else if (known.max() ?? 0) - (known.min() ?? 0) >= 30 {
            line("→ POSITION-DEPENDENT. Accumulated process state is implicated.")
        } else {
            line("→ FLAT. The T52 result was run-to-run variance, not position.")
        }
        line(rule("=", 72))
    }

    private static func isDecodeFailure(_ error: Error) -> Bool {
        if let generation = error as? LanguageModelSession.GenerationError,
           case .decodingFailure = generation {
            return true
        }
        return "\(error)".contains("decodingFailure")
    }

    /// Post-fix verification: does one retry actually clear the decode failure?
    ///
    /// The retry predicate is `RoundAgent.classify` itself rather than a copy,
    /// so this cannot drift from the behaviour it claims to measure.
    ///
    /// An attempt only counts if it produced a retry outcome. A first call that
    /// failed for a non-transient reason never entered the experiment, and a
    /// retry disturbed by one is not evidence that the retry does not work —
    /// both are EXCLUDED, so the rate is over attempts that actually tested it.
    static func retryProbe() async {
        line(rule("=", 72))
        line("RETRY PROBE — does one retry clear the RoundDecision decode failure?")
        line("\(attempts * 3) RoundDecision calls, retried once on a transient failure")
        line(rule("=", 72))

        guard case .available = SystemLanguageModel.default.availability else {
            line("model unavailable — halted"); return
        }

        var firstTry = 0, rescued = 0, failedTwice = 0, excluded = 0
        var moves: [String: Int] = [:]
        var excludedReasons: Set<String> = []

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
                guard case .transient = RoundAgent.classify(error) else {
                    excluded += 1
                    excludedReasons.insert(short(error))
                    line("  \(pad(i)): EXCLUDED    not a retryable failure — \(short(error))")
                    continue
                }
                do {
                    let r = try await once()
                    rescued += 1
                    moves[r.move.rawValue, default: 0] += 1
                    line("  \(pad(i)): OK ON RETRY \(r.move.rawValue)")
                } catch {
                    if case .transient = RoundAgent.classify(error) {
                        failedTwice += 1
                        line("  \(pad(i)): FAILED TWICE \(short(error))")
                    } else {
                        excluded += 1
                        excludedReasons.insert(short(error))
                        line("  \(pad(i)): EXCLUDED    retry hit an unrelated failure — \(short(error))")
                    }
                }
            }
        }

        let attempted = attempts * 3
        let scorable = firstTry + rescued + failedTwice
        line("")
        line(rule("=", 72))
        line("  scorable attempts       : \(scorable) of \(attempted)")

        if excluded > 0 {
            line("  ⚠️  \(excluded) EXCLUDED — failed for reasons the retry does not address:")
            for reason in excludedReasons.sorted() { line("     \(reason)") }
        }

        guard scorable >= minimumScorableForRetry else {
            line("")
            line("  INCONCLUSIVE — only \(scorable) of \(attempted) attempts tested the retry.")
            line("  A rate over this denominator would describe the excluded failures,")
            line("  not the retry. Fix the upstream failure and re-run.")
            line(rule("=", 72))
            return
        }

        line("  first attempt succeeded : \(firstTry)/\(scorable) (\(percent(firstTry, scorable))%)")
        line("  rescued by the retry    : \(rescued)")
        line("  failed twice            : \(failedTwice)")
        line("  EFFECTIVE FAILURE RATE  : \(percent(failedTwice, scorable))%"
             + "   (baseline before the retry landed: ~20–25%)")
        line("  moves: \(moves.map { "\($0.key)×\($0.value)" }.sorted().joined(separator: " "))")
        line(rule("=", 72))
    }

    private static func percent(_ part: Int, _ whole: Int) -> Int {
        whole == 0 ? 0 : Int((Double(part) / Double(whole)) * 100)
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
        different category. \
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

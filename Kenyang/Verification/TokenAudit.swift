import Foundation
import FoundationModels

// TESTS.md T50 / T51 / T52 — context accounting.
//
// Run with:  xcrun simctl launch --console <device> com.<bundle> --token-audit
//
// Every number here comes from SystemLanguageModel.tokenCount(for:) (iOS 26.4+),
// NOT from a characters/4 estimate. The 4,096-token window is shared by
// instructions + tools + schema + prompt + tool results + output.

enum TokenAudit {

    static let windowLimit = 4096
    static let passBar = 3000          // TESTS.md T51 pass bar

    // MARK: - Entry point

    static func run() async {
        line(rule("=", 72))
        line("KENYANG CONTEXT AUDIT — T50 / T51 / T52")
        line("started \(Date.now.formatted(date: .abbreviated, time: .standard))")
        line(rule("=", 72))

        let model = SystemLanguageModel.default
        line("")
        line("availability: \(describe(model.availability))")
        guard case .available = model.availability else {
            line("")
            line("HALTED — the model is not available, so nothing below can be measured.")
            line("This is guardrail layer 1 behaving correctly, not a harness failure.")
            return
        }

        await t51(model)
        await t52(model)
        await t50(model)

        line("")
        line(rule("=", 72))
        line("AUDIT COMPLETE")
        line(rule("=", 72))
    }

    // MARK: - T51 · token accounting per call site

    private static func t51(_ model: SystemLanguageModel) async {
        header("T51 — TOKEN ACCOUNTING PER CALL SITE",
               "How many tokens does each model call actually use?",
               "pass bar: every call < \(passBar) of \(windowLimit)")

        let input = Fixtures.midMealInput()

        // ---- fixed costs, shared by every call that carries them ----
        let instructions = Instructions(RoundAgent.instructions)
        let instructionTokens = await count(model) { try await model.tokenCount(for: instructions) }
        let toolTokens = await count(model) { try await model.tokenCount(for: AgentToolbox.readTools) }

        line("")
        line("FIXED COSTS (paid on every call that carries them)")
        row("instructions", instructionTokens)
        row("8 tool definitions", toolTokens)
        line("")
        line("  → any call carrying instructions + tools starts at "
             + "\(add(instructionTokens, toolTokens)) tokens before a single word of prompt.")

        // ---- call site 3: hypothesise ----
        let hypothesisPrompt = Fixtures.hypothesisPrompt(input)
        await measure(model,
                      site: "CALL 3 · hypothesise",
                      prompt: hypothesisPrompt,
                      schema: ValueHypothesis.generationSchema,
                      instructionTokens: instructionTokens,
                      toolTokens: toolTokens,
                      carriesTools: true) {
            let session = LanguageModelSession(tools: AgentToolbox.readTools,
                                               instructions: RoundAgent.instructions)
            _ = try await session.respond(to: hypothesisPrompt,
                                          generating: ValueHypothesis.self)
            return session
        }

        // ---- call site 3b: setIntent (no tools) ----
        let intentPrompt = Fixtures.intentPrompt(input)
        await measure(model,
                      site: "CALL 3b · setIntent",
                      prompt: intentPrompt,
                      schema: RoundIntent.generationSchema,
                      instructionTokens: instructionTokens,
                      toolTokens: 0,
                      carriesTools: false) {
            let session = LanguageModelSession(instructions: RoundAgent.instructions)
            _ = try await session.respond(to: intentPrompt, generating: RoundIntent.self)
            return session
        }

        // ---- call site 4: decide ----
        let decidePrompt = Fixtures.decidePrompt()
        await measure(model,
                      site: "CALL 4 · decide",
                      prompt: decidePrompt,
                      schema: RoundDecision.generationSchema,
                      instructionTokens: instructionTokens,
                      toolTokens: toolTokens,
                      carriesTools: true) {
            let session = LanguageModelSession(tools: AgentToolbox.readTools,
                                               instructions: RoundAgent.instructions)
            _ = try await session.respond(to: decidePrompt, generating: RoundDecision.self)
            return session
        }
    }

    /// Measures one call site: static costs first, then the real call, then the
    /// full transcript — which is the only number that includes tool results.
    private static func measure(_ model: SystemLanguageModel,
                                site: String,
                                prompt: String,
                                schema: GenerationSchema,
                                instructionTokens: Int?,
                                toolTokens: Int?,
                                carriesTools: Bool,
                                run: @escaping () async throws -> LanguageModelSession) async {
        line("")
        line(rule("─", 72))
        line(site)
        line(rule("─", 72))

        let promptTokens = await count(model) { try await model.tokenCount(for: Prompt(prompt)) }
        let schemaTokens = await count(model) { try await model.tokenCount(for: schema) }

        row("instructions", instructionTokens)
        if carriesTools { row("tool definitions", toolTokens) }
        row("output schema", schemaTokens)
        row("prompt", promptTokens)

        let before = [instructionTokens, carriesTools ? toolTokens : 0, schemaTokens, promptTokens]
            .compactMap { $0 }.reduce(0, +)
        row("BEFORE the call", before, emphasis: true)

        var elapsed: Duration = .zero
        var session: LanguageModelSession?
        var failure: String?

        do {
            let started = ContinuousClock.now
            session = try await run()
            elapsed = ContinuousClock.now - started
        } catch {
            failure = describe(error)
        }

        if let failure {
            line("  result           : FAILED — \(failure)")
            return
        }

        guard let session else { return }
        let entries = Array(session.transcript)
        let total = await count(model) { try await model.tokenCount(for: entries) }

        line("")
        row("AFTER the call (full transcript)", total, emphasis: true)
        if let total, let t = Optional(total) {
            let toolCost = t - before
            line("  ├─ tool calls + results + output add: \(toolCost >= 0 ? "+" : "")\(toolCost) tokens")
            line("  ├─ headroom left: \(windowLimit - t) of \(windowLimit)")
            line("  └─ VERDICT: \(t < passBar ? "PASS" : "FAIL") "
                 + "(\(t) vs \(passBar) bar, \(pct(t, windowLimit))% of window)")
        }
        line("  latency          : \(seconds(elapsed))s   ← T55 data point")
        line("  transcript entries: \(entries.count)")
    }

    // MARK: - T52 · tool-result accumulation in one session

    private static func t52(_ model: SystemLanguageModel) async {
        header("T52 — TOOL-RESULT ACCUMULATION",
               "CALL 4 asks for 3 tools in ONE session. Instructions, prompt, every",
               "tool call record, every tool result and the output all share the window.")

        // Repeat, because run 1 of this audit produced a decodingFailure here on a
        // call site that had just succeeded in T51 — so the question is not only
        // "does it fit" but "how often does the SAME call fail at all".
        let attempts = 8
        var successes = 0
        var totals: [Int] = []
        var failures: [String] = []

        for attempt in 1...attempts {
            let session = LanguageModelSession(tools: AgentToolbox.readTools,
                                               instructions: RoundAgent.instructions)
            do {
                let started = ContinuousClock.now
                _ = try await session.respond(to: Fixtures.decidePrompt(),
                                              generating: RoundDecision.self)
                let elapsed = ContinuousClock.now - started
                let entries = Array(session.transcript)
                let total = await count(model) { try await model.tokenCount(for: entries) }
                successes += 1
                if let total { totals.append(total) }
                line("  attempt \(attempt): OK   \(total.map(String.init) ?? "?") tok, "
                     + "\(entries.count) entries, \(seconds(elapsed))s")

                if successes == 1 {
                    line("")
                    line("  per-entry breakdown of the first successful transcript:")
                    var running = 0
                    for (i, entry) in entries.enumerated() {
                        let n = await count(model) { try await model.tokenCount(for: [entry]) }
                        running += n ?? 0
                        line("    \(i + 1). \(label(for: entry).padding(toLength: 16, withPad: " ", startingAt: 0))"
                             + " \((n.map(String.init) ?? "?").leftPadded(to: 5)) tok   (running \(running))")
                    }
                    line("")
                }
            } catch {
                failures.append(describe(error))
                line("  attempt \(attempt): FAIL — \(describe(error))")
            }
        }

        line("")
        line("  successes: \(successes)/\(attempts)")
        if let hi = totals.max(), let lo = totals.min() {
            line("  transcript tokens: \(lo)–\(hi) of \(windowLimit)  ·  "
                 + "VERDICT on context: \(hi < passBar ? "PASS" : "FAIL")")
        }
        if !failures.isEmpty {
            line("")
            line("  ⚠️  \(failures.count)/\(attempts) FAILED — and NOT on context:")
            for f in Set(failures) { line("     \(f)") }
        }
        line("")
        line("  Round 2+ replays this with MORE ratings in the prompt.")
        line("  Growth per extra rated dish is what decides whether a long meal survives.")
    }

    // MARK: - T50 · menu parse at real scale

    private static func t50(_ model: SystemLanguageModel) async {
        header("T50 — MENU PARSE AT REAL SCALE",
               "Does a 90+ item order-based AYCE menu fit in ONE call?",
               "pass bar: it fits, OR a chunk-by-category strategy is proven")

        line("")
        line("⚠️  INPUT IS SYNTHETIC — a representative 90-item grill-AYCE menu in the")
        line("   printed categories from BUFFET.md §4, not a photograph of a real one.")
        line("   That makes this a SIZING measurement, which is scale-accurate, and NOT")
        line("   an accuracy measurement. Parse accuracy on real OCR text is T53, and it")
        line("   needs the menu photos, which are not in the repo. Principle 22 applies.")

        let menuText = Fixtures.syntheticMenu()
        line("")
        line("menu: \(Fixtures.menuItemCount) items, \(menuText.count) characters")

        let prompt = Fixtures.menuParsePrompt(menuText)
        let promptTokens = await count(model) { try await model.tokenCount(for: Prompt(prompt)) }
        let schemaTokens = await count(model) { try await model.tokenCount(for: ParsedMenu.generationSchema) }

        line("")
        row("parse prompt", promptTokens)
        row("output schema", schemaTokens)
        if let p = promptTokens, let s = schemaTokens {
            line("  → input side alone: \(p + s) of \(windowLimit) "
                 + "(\(pct(p + s, windowLimit))% before a single item is emitted)")
            line("  → 90 items must then be GENERATED into the same window.")
        }

        line("")
        line("attempting the whole menu in one call…")
        do {
            let started = ContinuousClock.now
            let result = try await LanguageModelSession(instructions: Fixtures.menuParseInstructions)
                .respond(to: prompt, generating: ParsedMenu.self)
            let elapsed = ContinuousClock.now - started
            line("  RESULT: returned \(result.content.items.count) of "
                 + "\(Fixtures.menuItemCount) items in \(seconds(elapsed))s")
            if result.content.items.count < Fixtures.menuItemCount {
                line("  ⚠️  SHORT — it did not emit every item. Chunking is required anyway.")
            }
        } catch {
            line("  RESULT: FAILED — \(describe(error))")
            line("  → this is the expected outcome, and it is what T50 exists to prove.")
        }

        // The fallback the pass bar asks for.
        line("")
        line("attempting chunk-by-category (the fallback strategy)…")
        var returnedNames: [String] = []
        var chunkFailures = 0
        var mismatches: [String] = []

        for (category, lines) in Fixtures.menuByCategory() {
            let chunkPrompt = Fixtures.menuParsePrompt(lines.joined(separator: "\n"))
            do {
                let r = try await LanguageModelSession(instructions: Fixtures.menuParseInstructions)
                    .respond(to: chunkPrompt, generating: ParsedMenu.self)
                let out = r.content.items.map(\.name)
                returnedNames += out
                let matched = out.count == lines.count
                if !matched {
                    mismatches.append("\(category): \(lines.count) in, \(out.count) out")
                }
                line("  \(matched ? " " : "!") \(category.padded(to: 22)) "
                     + "\(lines.count) in → \(out.count) out")
            } catch {
                chunkFailures += 1
                line("  ✗ \(category.padded(to: 22)) FAILED — \(describe(error))")
            }
        }
        let expected = Fixtures.menuByCategory().flatMap(\.1).map(normalised)
        let returned = returnedNames.map(normalised)
        let invented = Set(returned).subtracting(expected).sorted()
        let missed = Set(expected).subtracting(returned).sorted()
        let duplicated = Dictionary(grouping: returned, by: { $0 })
            .filter { $0.value.count > 1 }
            .keys.sorted()

        line("")
        line("  chunked total     : \(returnedNames.count) of \(Fixtures.menuItemCount) items")
        line("  category failures : \(chunkFailures)")
        line("  count mismatches  : \(mismatches.count)")
        for m in mismatches { line("     \(m)") }
        if !invented.isEmpty {
            line("  INVENTED — returned but not printed on the menu: \(invented.joined(separator: ", "))")
        }
        if !missed.isEmpty {
            line("  MISSED — printed but not returned: \(missed.joined(separator: ", "))")
        }
        if !duplicated.isEmpty {
            line("  DUPLICATED: \(duplicated.joined(separator: ", "))")
        }

        let faithful = chunkFailures == 0 && invented.isEmpty && missed.isEmpty && duplicated.isEmpty
        line("  VERDICT: \(faithful ? "chunking WORKS — every printed item returned exactly once, nothing invented" : "chunking is NOT reliable — see the lines above")")
    }

    // MARK: - Output helpers

    private static func header(_ title: String, _ lines: String...) {
        line("")
        line("")
        line(rule("█", 72))
        line("█ \(title)")
        for l in lines { line("█ \(l)") }
        line(rule("█", 72))
    }

    private static func row(_ label: String, _ value: Int?, emphasis: Bool = false) {
        let text = value.map { "\($0)" } ?? "unavailable"
        let marker = emphasis ? "▶ " : "  "
        line(marker + label.padding(toLength: max(34, label.count), withPad: " ", startingAt: 0)
             + ": " + text.leftPadded(to: 5) + " tokens")
    }

    private static func count(_ model: SystemLanguageModel,
                              _ body: () async throws -> Int) async -> Int? {
        do { return try await body() } catch { return nil }
    }

    private static func add(_ a: Int?, _ b: Int?) -> String {
        guard let a, let b else { return "?" }
        return "\(a + b)"
    }

    private static func pct(_ n: Int, _ d: Int) -> Int { Int((Double(n) / Double(d)) * 100) }

    private static func seconds(_ d: Duration) -> String {
        String(format: "%.1f", Double(d.components.seconds)
               + Double(d.components.attoseconds) / 1e18)
    }

    private static func label(for entry: Transcript.Entry) -> String {
        switch entry {
        case .instructions:   "instructions"
        case .prompt:         "prompt"
        case .toolCalls:      "tool calls"
        case .toolOutput:     "TOOL RESULT"
        case .response:       "response"
        @unknown default:     "unknown"
        }
    }

    private static func describe(_ availability: SystemLanguageModel.Availability) -> String {
        switch availability {
        case .available: "available"
        case .unavailable(let reason): "unavailable — \(reason)"
        @unknown default: "unknown"
        }
    }

    private static func describe(_ error: Error) -> String {
        let text = "\(error)"
        if text.contains("exceededContextWindowSize") { return "exceededContextWindowSize — THE WINDOW RAN OUT" }
        if text.contains("guardrailViolation") { return "guardrailViolation (the ~10% non-deterministic block)" }
        if text.contains("unsupportedLanguageOrLocale") { return "unsupportedLanguageOrLocale" }
        return String(text.prefix(400))
    }

    private static func line(_ s: String) {
        print("[AUDIT] \(s)")
        fflush(stdout)
    }
}

// MARK: - Menu parse types (Module A is not built; these are the minimum to size it)

@Generable
enum MenuCategory: String, Codable, CaseIterable, Sendable {
    case appetizerAgemono, grillAppetizer, standardMeat, premiumMeat
    case salad, sushi, riceAndNoodle, soup, vegetables, dessert
}

@Generable
struct MenuItemDraft: Sendable {
    @Guide(description: "The item name exactly as printed on the menu")
    var name: String

    @Guide(description: "The printed menu category this item appears under")
    var category: MenuCategory
}

@Generable
struct ParsedMenu: Sendable {
    @Guide(description: "Every item on the menu, one entry each")
    var items: [MenuItemDraft]
}

// MARK: - Small string helpers

private func rule(_ c: String, _ n: Int) -> String {
    String(repeating: c, count: Swift.max(0, n))
}

private extension String {
    func leftPadded(to width: Int) -> String {
        count >= width ? self : String(repeating: " ", count: width - count) + self
    }

    func padded(to width: Int) -> String {
        count >= width ? self : self + String(repeating: " ", count: width - count)
    }
}

private func normalised(_ name: String) -> String {
    name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}

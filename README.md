# Kenyang

**An agentic utility app for sequential decision-making under gastric constraint.**

A buffet is explore–exploit under a knapsack constraint where observation costs budget. Kenyang treats it as one: an on-device agent forms a claim about where the value is concentrated, commits to an expected rating *before* tasting, plans a round against that objective, and revises when the diner's own ratings falsify it.

Scope is **order-based, grill-at-your-table all-you-can-eat** — you order from a fixed printed menu, staff bring the food, you cook it at the table.

Built for a seven-criterion challenge on Apple Intelligence and Apple system technologies. Everything runs on device.

---

## Stack

| | |
|---|---|
| SwiftUI · SwiftData · FoundationModels · AppIntents | Swift 6.3 |
| Xcode 26.6 · iOS SDK 26.5 | Foundation Models context window: **4,096 tokens** |

`SWIFT_DEFAULT_ACTOR_ISOLATION` is set to `nonisolated`. The Xcode 26 template defaults to `MainActor`, which makes `AppEnum` and `AppEntity` conformances main-actor-isolated and therefore not `Sendable` — App Intents require the opposite.

**Built on iOS 26 stable, deliberately.** WWDC26 shipped an agentic layer — `DynamicProfile`, `DynamicInstructions`, `ToolCallingMode`, mutable transcripts, an Evaluations framework — but it requires iOS 27 / Xcode 27 beta, with GA landing inside or after this project's window. The orchestration here is hand-rolled and maps onto those APIs.

---

## Layout

```
Kenyang/
├── App/
│   └── KenyangApp.swift          @main, container, AppDependencyManager,
│                                 launch-argument harness dispatch
├── Models/                       no behaviour beyond derivation
│   ├── Domain.swift              closed-set enums, FlavourProfile, CapacityState
│   ├── Persistence.swift         @Model entities + KenyangSchema
│   └── KenyangStore.swift        the single data access point
│
├── Engine/                       deterministic Swift — the model never computes
│   ├── CapacityEngine.swift      satiety accounting, fullness prediction
│   ├── ValueEngine.swift         posteriors, value density, satiety discount
│   └── RoundPlanner.swift        bounded beam search
│
├── Agent/
│   ├── AgentTypes.swift          @Generable contracts, TraceLog
│   └── RoundAgent.swift          the state machine
│
├── Tools/
│   └── AgentTools.swift          8 Tool conformances + ToolContext actor
│
├── Guardrails/
│   └── Guardrails.swift          8 layers, each independently testable
│
├── ViewModels/
│   └── SessionViewModel.swift    @Observable, owns phase and session state
│
├── Views/
│   ├── SessionView.swift         Root, Start, Plan, Eating, Terminal, Trace
│   └── VerificationView.swift    the in-app battery
│
├── Intents/
│   ├── Entities.swift            AppEntity + EntityQuery
│   └── KenyangIntents.swift      intents, snippets, AppShortcutsProvider
│
└── Verification/                 measurement harnesses — launch-argument driven
    ├── TokenAudit.swift          context measurement via tokenCount
    ├── SchemaProbe.swift         guided-generation failure, field order, retry
    ├── StanceProbe.swift         prompt injection, grounding, volume framing
    ├── GrowthAudit.swift         per-call-site token/latency/transcript budgets
    └── AuditFixtures.swift       mid-meal state, 95-item synthetic menu
```

**Code carries no comments by design.** This file is the explanation.

---

## Architecture

### Store events, derive state

`TasteEvent` is the source of truth. Capacity remaining, satiety state, value density, round number and break-even are **computed** from the event log, never persisted.

The satiety model is still unvalidated. If derived values were stored, changing the model would be a data migration; because they are derived, it is a re-render.

### The model chooses the objective; Swift computes the optimum

This resolves the tension between *the model never computes* and *if your code decides what happens next, the decision left the agent.* The seam is the objective function.

```
[FM] ValueHypothesis  →  where is the value, and what rating do I expect?
[FM] RoundIntent      →  what is this round FOR?    ← the policy decision
     RoundPlanner     →  beam search optimises THAT objective
```

`PlannerObjective` parameterises the scoring function: recon share, what is worth learning, which flavour axis to avoid, how much variance to accept. Beam search finds the optimum; **it does not choose what is being optimised.**

**Diagnostic:** replace the model's output with a constant. If the plan is unchanged, the agent is decorative.

### The state machine

```
TRIAGE       is there a decision problem here at all?   → declineToOptimise
STOP CHECK   is capacity or seating time gone?          → recommendStop
AVAILABILITY is the model there?                        → degraded mode
HYPOTHESISE  compose a claim, commit expectedRating BEFORE tasting
SET_INTENT   what is this round for
PLAN         beam search under that objective
OBSERVE      the diner rates what they ate
DECIDE       exploit · pivot, given a verdict the model did not author
```

Path length varies: a run can terminate at `TRIAGE`, at any `STOP CHECK`, or after 1–6 rounds.

---

## The tools

Eight `Tool` conformances passed to `LanguageModelSession(tools:)`. `ToolContext` is an `actor` holding the deterministic state the tools read, and recording which were invoked — so *every listed tool is invoked in a logged run* is measurable rather than asserted.

| Tool | Can refuse |
|---|---|
| `getSpread` | |
| `getPosterior` | returns `insufficient` below minimum *n* |
| **`evaluateHypothesis`** | **supported · contradicted · insufficient** |
| **`checkCapacityModel`** | **consistent · over · under · insufficient** |
| `getRemainingCapacity` | |
| **`getBasisCalibration`** | **`insufficient` until n ≥ 8** |
| `getConstraints` | |
| `getVisitHistory` | |

Three independent falsification axes: the **value** claim, the **budget** the plan is spent against, and **the agent's own reasoning history**.

---

## The guardrails

Each is a separate type, so each can be tested and demonstrated in isolation.

| Layer | Type | Behaviour |
|---|---|---|
| 1 Availability | `ModelAvailability` | Distinguishes not-enabled, downloading and unsupported; each gets its own message and a real degraded path |
| 2 Input trust | `RoundAgent.instructions` | Dish and station names are declared untrusted data, and only ever enter prompts — never `Instructions` |
| 3 Structural | `@Generable` enums | The model cannot invent a station or a basis |
| 4 Grounding | `OutputValidator` | Rejects volume framing before display |
| 5 Statistical | `StatisticalGuard` | No claim below minimum *n* |
| 6 Action | `ExclusionValidator`, `StopGuard`, `TriageGuard` | Ternary exclusion; forced stop; forced decline |
| 7 Loop | `LoopBudget`, `AskBudget` | Max rounds, max calls per round, three questions per meal |
| 8 Safety | `RoundAgent.retrying(_:)`, `describe(_:)` | One retry on transient generation failures; violations and locale errors surfaced as `.modelFailure`, never as a decision |

### Three of these exist because measurement demanded them

**`StopGuard` and `TriageGuard` force stopping and declining.** Across the day-3 spike the model chose `stop` 0/3 times and `decline` 0/2 times, even handed exhausted capacity. It recognises support well and contradiction moderately, but **it will not choose to end the meal.** So the app computes those deterministically and overrides. A guardrail overriding an agent is legitimate; Swift *choosing the next action* would not be — the distinction is that this fires on a threshold, not on a judgement.

**`OutputValidator` exists because instructions alone did not hold.** A prompt-injection test compromised the app's core stance — *"eat as much as possible to get your money's worth"* — which the design forbids by name. Instruction hardening is necessary and insufficient; the claim is now checked before display.

**`ConsistencyGuard` catches the model contradicting itself.** Observed repeatedly: the reasoning field correctly says *"the tools say the hypothesis is contradicted"* and the move field then says `exploit`. When the stated reason disagrees with the chosen move, the move is overridden.

### The exclusion validator is ternary

```
safe      ingredients determinable, no exclusion hit  → plannable
excluded  ingredients determinable, exclusion hit     → discarded before display
unknown   ingredients not determinable                → never planned silently
```

A binary validator fails open: *"I could not determine this"* silently becomes *safe*, which is the one direction that is unrecoverable. `unknown` dishes are surfaced with a defer-to-staff prompt instead.

The exclusion list is **an input, never an inference** — the app takes ingredients and never asks why an item is on the list.

---

## Running it

Open `Kenyang.xcodeproj` and run. Requires a device or simulator with Apple Intelligence available; the app has a real degraded path when it is not.

**In-app:** the **Verify** toolbar button runs the battery and shows results on device.

**Headless.** Every harness prints to the console and exits:

```bash
xcrun simctl launch --console-pty <device> com.hansjoachim.Kenyang --run-all
```

App battery → context audit → stance probe → growth audit → schema/position/retry probes. Roughly 12 minutes on iPhone 17 / iOS 26.5. Individually: `--verify` `--token-audit` `--stance-probe` `--growth-audit` `--schema-probe` `--position-probe` `--retry-probe`.

**These are measurement, not tests.** There is no test target and they produce numbers rather than assertions.

---

## What has actually been measured

Dates matter here; every figure below is from a logged run, not an estimate.

| | |
|---|---|
| Tool calling | **8/8 tools invoked** by the model, unprompted |
| Falsification tools returning a negative | **3/3** |
| Guardrail layers shown firing | **4** — availability, structural, statistical, exclusion |
| A hypothesis dying, then pivoting | ✅ `rawBar → grill` |
| Path variance | 3 distinct terminals over 4 runs |
| Cold start at n = 0 | ✅ |
| Context, worst call site | **42% of the 4,096 window** against a 3,000 pass bar |
| `RoundDecision` guided-generation decode | 75–86% first attempt → **0–8% effective** after retry |

### Context is not the constraint — on the input side

Every figure comes from `SystemLanguageModel.tokenCount(for:)`, not a `characters / 4` estimate.

Two consequences that shape the codebase:

1. **Tool definitions cost ~97 tokens each — 774 for the current eight.** That is the largest single line item in the window, paid on every tool-carrying call. Price a tool in tokens before adding it.
2. **Tool results are cheap** — 11–28 tokens each. The preamble is 86% of a `decide` transcript. The constant dominates, not accumulation.

### The output side is not settled

`setIntent` threw `.exceededContextWindowSize` **from a 539-token start** (2026-09-07). `RoundIntent.rationale` is a free `String` with no length `@Guide`, so the model generated until the window ended and killed the session. Not an input problem. **Cap every free-text `@Generable` field.**

### `RoundDecision` fails guided generation, and why the fix is a retry

The model emits correct reasoning as prose instead of JSON. Two candidate causes were tested and **both rejected** — rewriting the `@Guide` text declaratively made it *worse* (12/12 → 6/12), and failure did not accumulate with session state (91% → 75% → 83%, flat). So the fix is `retrying(_:)`, one retry on `decodingFailure` or `guardrailViolation`, consuming loop budget so it cannot run away.

It mattered more than the rate suggested: `decide()` caught the error and returned the **unchanged hypothesis**, so one decision step in five silently became *"carry on"* — indistinguishable from `exploit`. A decode failure now degrades to the deterministic tool verdict instead, attributed in the trace as taken on the tool's authority alone, and recorded as `TraceKind.modelFailure` rather than `.guardrail`. **A guardrail firing is the system working; a decode failure is not, and the trace must not conflate them.**

**The theory behind the fix was still partly wrong.** The swallow was *not* what produced the exploit bias — with it gone, `exploit` is still ~92% (65/71). The guards stay load-bearing.

An incidental finding worth keeping: three failures began `DecisionB{"because": …` — **the `@Generable` type's own name leaked into the generated text** and broke the JSON. Prefer type names that read like domain nouns.

---

## Honest status

### Working

Session start · spread capture · tool-calling agent · hypothesis with pre-registered expectation · round objective · beam-search planning · rating · capacity accounting · trace panel with computed-vs-model attribution · four App Intents with an entity, an interactive snippet and shortcut phrases.

### Known defects, ranked

1. **Unbounded `@Generable` output can kill the session** — no length `@Guide` on free-text fields; `.exceededContextWindowSize` is not handled in `retrying(_:)`.
2. **`RoundDecision` decode failure** — 8% residual after retry, degrading to the tool verdict.
3. **The chunked menu parse invents items** — 96 returned from 95. The harness reported zero failures because it checked that chunks parsed, not that counts matched.
4. **The domain vocabulary predates the adopted scope** — `StationCategory`, `isRationed`, `isMadeToOrder`, `ValueBasis.scarcity` were replaced by printed-menu categories and `tierExclusivity` in the design and not yet in code.
5. **Latency** — `hypothesise` 18.8–30.1 s; a round 25–36 s against a ~3 s budget, and that is a Simulator floor.
6. **`LoopBudget.wallClockLimit` is declared and never read** — layer 7 enforces call count only, and one `hypothesise` can eat the whole 20 s budget.
7. **`CapacityEngine.fittedMax` fits on censored data** — see below.
8. Capture is a hardcoded `DemoSpread`; the real path is a one-time menu parse.
9. No Live Activity, Control Center control, widget, Focus filter or background task yet.
10. Grill constraints — slots, cook time, plain-before-marinated — are designed, not implemented in `RoundPlanner`.

### The capacity model has a defect that would not announce itself

`CapacityEngine.fittedMax(from:)` averages the cumulative satiety of completed visits. **Those totals are lower bounds, not observations** — a meal that ended because the seating expired says only `S_max ≥ that total`. Averaging censored with uncensored data biases `S_max` **downward, and worse the more the app is used**, while every screen keeps looking correct.

`checkCapacityModel` already returns `consistent · over · under · insufficient` from this comparison. **The tool fires; the update rule behind it does not exist.** The app can detect that its capacity model is wrong and cannot yet learn from it.

### Agency level

Deliberately not claimed here yet. What is measured: the agent composes rather than selects its hypothesis, path length varies with the data, tool verdicts bind, and it can decline the premise — but `exploit` is chosen ~92% of the time, and the 20-scenario branch-selection battery has not been run. **The level claim waits on that measurement.** Overclaiming is the fastest way to lose credibility with anyone who probes.

---

## A note on the palette

The app is Alabaster Grey `#E5E4E2` / Onyx `#0A0A0A` / Blue Slate `#536878`, and the warm option was rejected on the stance rather than on taste.

Saturated red-orange — `#AA0003`, `#FF4500`, `#FF6B6B` — is the appetite palette, the one fast-food branding uses to drive consumption. The design forbids volume framing by name and `OutputValidator` enforces it in code. **Shipping the colour of "eat more" while the copy says "stop before you regret it" would contradict the app's own guardrail.**

Onyx `#0A0A0A` is also the Dynamic Island, which is the primary in-meal interface — a near-black base reads as part of the hardware rather than a window on top of it, and survives a dim grill-at-your-table room.

One trap, recorded because it is easy to walk into: Blue Slate `#536878` is the brand accent and **fails body text on Onyx at 3.4:1**. Dark mode uses Blue Slate Light `#7C93A6` (6.2:1) instead. Colour is never the only indicator — every exclusion state carries a word: *safe* · *excluded* · *ask staff*.

---

## Design record

The full record — design rationale, the rubric decoder, the test register with every measurement, and a 39-page design document — lives outside this repository, alongside it in the parent directory:

```
Challenge-3/
├── Prompts/     HANDOFF.md · TESTS.md · PROJECT.md · DESIGN.md · DESIGN-V2.md
├── Designs/     C3 Design V1.2.pdf   ← the complete design record
├── Ideas/       BUFFET.md (design) · CRITERIA.md (rubric decoder)
├── Spike/       the day-1 harness and run logs
└── Kenyang/     this repository
```

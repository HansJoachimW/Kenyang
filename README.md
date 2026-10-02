# Kenyang

**An agentic utility app for sequential decision-making under gastric constraint.**

> **Kenyang** *(adj., Indonesian)* — pleasantly full, satisfied. It names the goal state, which is also the app's ethical stance: **the target is kenyang, not maximum.**

An all-you-can-eat meal is explore–exploit under a knapsack constraint where observation costs budget. Kenyang treats it as one: an on-device agent forms a claim about where the value is concentrated, commits to an expected rating *before* tasting, plans a round against that objective, and revises when the diner's own ratings falsify it. It tells you when to stop.

**Everything runs on device** — the agent, the planner and the capacity model. There are no network calls anywhere in the app.

*Built for Challenge 3 of the Apple Developer Academy: an agentic utility app using Apple Intelligence, graded on seven criteria — Human-Centered AI, custom App Intents, Siri / Shortcuts / Spotlight, Foundation Models, tool calling, guardrails and agentic workflows.*

**Contents:** The problem · The stance · How a meal works · Stack · Layout · Architecture · The tools · The guardrails · Where each criterion lives · Running it · What has been measured · Honest status · Agency level · Limitations

---

## The problem

### The domain

**Order-based, grill-at-your-table all-you-can-eat.** A fixed printed menu, ordered in rounds, brought by staff, cooked at the table, under a printed time limit and usually a tier price ladder. The venues are Surabaya's **Gyu-Kaku** (Japanese BBQ) and **Mashu** (Korean BBQ) and their near-identical competitors.

**Not** self-serve buffets. The project started there and was narrowed on 2026-09-04 by measurement: reading dishes off photographed placard text scored **6/20 correct and 6/20 confidently wrong**, and the model's honest *"unknown"* collapsed from 7/20 to 1/20 — more confident as it got more wrong. An order-based venue prints everything that was uncertain:

| Was uncertain (self-serve) | Is printed (order-based) |
|---|---|
| Dish identity, from a photographed placard | The printed menu |
| Category, inferred by the model | The menu's own sections |
| Portion size, ±30% | Standard — a plate of karubi is the same plate every time |
| Value, proxied from how the house rations | A published **price ladder** |
| Time | **90 minutes**, printed, last order at 75 |

### Why it is a real decision problem

This is not a joke framing. The structure is textbook:

* **Finite capacity** — the knapsack.
* **Unknown payoffs** — a dish's quality is unobservable until eaten.
* **Observation costs capacity** — tasting to learn spends the very budget being optimised. In a standard bandit, pulling an arm is free; here it is not, which is what makes it interesting.
* **A shrinking budget** — exploration must front-load and exploitation back-load.
* **An adversarial house** — rice, noodles and soup are unlimited and cheap, the premium cuts that justify the tier cook slowest, and the clock is set so a badly sequenced meal runs out of time before it runs out of stomach.

**Humans solve this badly and predictably**: over-explore in round one, fill up on filler, regret it by round three.

**The reward is state-dependent.** Sensory-specific satiety (Rolls et al., 1981): repeated exposure to a flavour lowers its pleasantness relative to foods not yet eaten. The fourth plate of the same dish delivers a fraction of the first, and a different dish of lower objective quality can beat it. So the problem is **sequencing, not selection** — what to order *next*, given that every choice changes the value of every later one.

---

## The stance

* **Kenyang, not maximum.** The app makes a meal better, not bigger. Volume framing (*"eat as much as you can"*, *"get your money's worth"*) is forbidden by name and enforced in code — `OutputValidator` blocks it in anything the model writes. Money is stated once, as a fact, at the stop.
* **Stopping is a first-class output**, not a failure. When capacity or time runs out, the app says stop, and it uses the accent colour, never red.
* **The invisibility constraint.** It is used at a table, with other people; any interaction over about three seconds ruins the meal it is meant to improve. That is why the Action Button, Siri and the Live Activity are the primary interface and the app's own screens are secondary.
* **Neutral about the person, opinionated about the food.** No streaks, no scores, no praise for restraint.
* **The avoid list is an input, never an inference.** It takes ingredients, never asks why, and never guesses an ingredient list — an unknown dish is held back and asked about.

---

## How a meal works

```
START           the app, the home-screen widget or Siri, always from the default
                menu (Gyu-Kaku Standard, 53 dishes, Rp 248,800, 90 min) and the
                diner's own plates-per-meal answer · "Still avoiding these?" in the app
ROUND           the agent GUESSES where the value is and commits to an expected
                rating · SETS THE GOAL for the round · Swift PLANS the orders under
                it: 1 order to learn an untried dish, up to 3 of a dish your ratings back
                → Accept · Adjust (tell it which way) · Stop, in the app or on the
                  Live Activity (Order these · Another)
EAT             log plates (+ / −, Action Button, Siri, the Island) and rate each
                dish once per round — rating again replaces it. Skip on a dish nobody
                ate passes on it: no plate, no room spent, no rating
DECIDE          next round, from the app or the Live Activity: the tools say whether
                the guess held → stay or change course
STOP            capacity or seating time gone → the app says stop, then asks why
```

**Who owns which moment** — the app's own screens own only two of them:

| Moment | Surface |
|---|---|
| Sitting down | **Home-screen widget** (Start) or the app; the **Control Center** control opens the app |
| Each round | **The app**, the **Live Activity** (Next round · Order these · Another · ingredient questions), or the **Siri snippet** |
| Eating | **Dynamic Island** / **Lock Screen** Live Activity · **Action Button** · **Siri** |
| At a glance | **Home-screen widget** · Spotlight for any dish |
| The stop | **The app** — and the one question worth asking: why did the meal end? The widget and the Live Activity can end a meal in one tap, recorded as *unknown* |

---

## Stack

| | |
|---|---|
| SwiftUI · SwiftData · FoundationModels · AppIntents · ActivityKit · WidgetKit | Swift 6.3 |
| Xcode 27.0 · iOS SDK 27.0 · **deployment target 26.5, both targets** | Foundation Models context window: **4,096 tokens** |
| Development phone | iPhone 17 · **iOS 27.0.1** since 2026-10-01 — every phone figure below was measured on iOS 26 |

`SWIFT_DEFAULT_ACTOR_ISOLATION` is set to `nonisolated`. The Xcode template defaults to `MainActor`, which makes `AppEnum` and `AppEntity` conformances main-actor-isolated and therefore not `Sendable` — App Intents require the opposite.

**The baseline is iOS 26; iOS 27 is taken when it is there.** Everything that differs sits behind `#available` in `AgentCapabilities`, the only place that branches — and the active tier is written into the trace:

| | iOS 26 | iOS 27 |
|---|---|---|
| *"You must call the tools"* | an instruction, complied with 8/8 in a logged run | still an instruction — `ToolCallingMode.required` kept the model calling tools until the 4,096-token window overflowed, so it is not used |
| A failed generation | the wrecked turn stays in the transcript | `.revertTranscript` — rolled back, the retry starts clean |
| Model errors | `GenerationError` | also `LanguageModelError`; an overflow or guardrail failure is mapped to the same retry rules |

---

## Layout

**Two targets.** `KenyangWidgets` renders the Live Activity, the Island, the widget family and the Control Center control. `KenyangWidgets/Shared/` belongs to **both** targets — that is how the extension gets the ring, the tokens and the activity contract without importing the model layer.

```
Kenyang/
├── Kenyang/                          the app target
│   ├── App/                          @main, dependency setup, MealCommandHandler for widget and Live Activity buttons
│   ├── Models/
│   │   ├── Domain.swift              closed-set enums, each carrying its own display label
│   │   ├── Persistence.swift         @Model entities; stored properties are never renamed
│   │   ├── KenyangStore.swift        reads and writes SwiftData, nothing else
│   │   ├── MealSession.swift         the meal in progress: round, plan, plates, ratings, skips, answers
│   │   ├── BuffetMenu.swift          the default menu every meal starts from
│   │   └── DinerPreferences.swift    the diner's plates-per-meal answer
│   ├── Engine/                       pure Swift: capacity, value, the planner, tiers, the avoid-list verdict
│   ├── Agent/                        RoundAgent, RoundCoordinator (the one place rounds are planned), @Generable types, the trace
│   ├── Tools/AgentTools.swift        8 Tool conformances + the ToolContext actor
│   ├── Guardrails/                   ClaimGuards · DecisionGuards · MealGuards · LoopBudget · ModelAvailability
│   ├── Activity/                     LiveActivityController, the MealDisplay for the Live Activity and widget
│   ├── ViewModels/MealViewModel.swift  which screen is showing
│   ├── Views/                        one file per screen, plus shared Components
│   ├── Intents/                      App Intents, entities, snippet, Action Button, shortcuts, Focus filter
│   └── Proactive/                    the arrival and morning-of trigger, and its silences
├── KenyangWidgets/                   the extension: Live Activity, widget, Control Center control
│   └── Shared/                       in BOTH targets: ActivityBridge, CapacityRing, DesignTokens, MealSnapshot, RoundActivityAttributes
└── KenyangTests/                     Swift Testing unit tests for the rules
```

---

## Architecture

### Store events, derive state

`TasteEvent` — **one plate eaten**, rated or not — is the source of truth. Capacity remaining, value, round number and break-even are **computed** from the event log, never persisted. The satiety model is still unvalidated; because values are derived, changing the model is a re-render, not a data migration.

### One meal, many surfaces

The app, the Live Activity, the widget, Siri and the Action Button all act on the meal through **one `MealSession`**, and every round is planned through **one `RoundCoordinator`**, so a rule (skip, the order cap, one rating per round, the round number) exists once. `KenyangStore` only persists. The session mirrors itself onto the Live Activity and the widget through the `MealDisplay` protocol, which the tests replace with a stand-in. `MealViewModel` only decides which screen shows.

### The model chooses the objective; Swift computes the optimum

This resolves the tension between *the model never computes* and *if your code decides what happens next, the decision left the agent.* The seam is the objective function:

```
[FM] ValueHypothesis  →  where is the value, and what rating do I expect?
[FM] RoundIntent      →  what is this round FOR?    ← the policy decision
     RoundPlanner     →  beam search optimises THAT objective, order by order
```

`PlannerObjective` parameterises the scoring: recon share, what is worth learning, which flavour to avoid, how much risk to accept. Beam search finds the best set of **orders**; **it does not choose what is being optimised.** A path may repeat a dish, and the satiety discount prices the repeat, so a second plate of the same thing scores below the first. An untried dish is one order; a dish the ratings back may get up to three; the round's capacity budget is the real limit.

**Diagnostic:** replace the model's output with a constant. If the plan is unchanged, the agent is decorative.

### Adjust re-runs the policy step, not the claim

When the diner rejects a plan they say which way — *try new things · more of what I liked · play it safe*. Only `SET_INTENT` runs again, with the rejected objective and that direction as input. **The hypothesis is untouched**: a rejected plan is not evidence about where the value is — only ratings are. `AdjustGuard` checks the new objective actually moved the asked way and steps it itself if not. Adjust restarts the round's wall clock (it bounds the agent's thinking, not the diner's reading) but not its call count.

### The state machine

```
TRIAGE       is there a decision problem here at all?   → declineToOptimise
STOP CHECK   is capacity or seating time gone?          → recommendStop
AVAILABILITY is the model there?                        → degraded mode
HYPOTHESISE  compose a claim, commit expectedRating BEFORE tasting
SET_INTENT   what is this round for
PLAN         beam search under that objective
OBSERVE      the diner logs plates and rates dishes
DECIDE       exploit · pivot, given a verdict the model did not author
```

A run can end at `TRIAGE`, at any `STOP CHECK`, or after several rounds.

### MVVM boundaries

| Layer | Rule |
|---|---|
| **Model** | SwiftData entities and value types. No SwiftUI, no agent knowledge |
| **Engine** | Pure functions over models. No I/O, no async, no model calls |
| **Agent** | Owns the state machine and the `@Generable` contracts. Never touches SwiftData directly |
| **ViewModel** | `@MainActor @Observable`. Translates user actions into store writes and agent runs |
| **View** | Renders the phase. No business logic |
| **Intents** | Resolve `KenyangStore` through `AppDependencyManager` — they run outside the app's UI |

**Code carries no comments by design, except where a decision needs its reason next to it.** This file is the explanation.

---

## The tools

Eight `Tool` conformances passed to `LanguageModelSession(tools:)`. `ToolContext` is an actor holding the deterministic state the tools read, and it records which were invoked — so *every tool is invoked* is measured, not asserted.

| Tool | Can refuse |
|---|---|
| `getSpread` | |
| `getPosterior` | `insufficient` below 2 ratings in the category |
| **`evaluateHypothesis`** | **supported · contradicted · insufficient** |
| **`checkCapacityModel`** | **consistent · over · under · insufficient** |
| `getRemainingCapacity` | |
| **`getBasisCalibration`** | **`insufficient` until n ≥ 8** |
| `getConstraints` | |
| `getVisitHistory` | |

**Three independent falsification axes:** the value claim, the capacity the plan is spent against, and the agent's own reasoning history. *Insufficient* is the statistical guard working — one rating is an anecdote.

**Round 1's guess gets only `getSpread`, `getConstraints` and `getRemainingCapacity`.** Before anything is rated the other five can only answer *insufficient*, and the model kept asking them. **The guess looks up first, then answers:** one call with the tools and a plain-text answer, a second for the typed `ValueHypothesis`. With tools and the typed answer in one call, the iPhone's iOS 27 model called tools until its 4,096-token window overflowed (38 calls; 5 of 5 runs); split, it answers in 5.6–8.7 s (5 of 5).

**Each tool definition costs ~97 tokens — 774 for the eight — paid on every tool-carrying call** (iOS 26 figure; on the iOS 27 phone the eight cost 852, the round-1 three 358). Price a tool in tokens before adding one.

---

## The guardrails

| Layer | Type | Behaviour |
|---|---|---|
| 1 Availability | `ModelAvailability` | Not enabled, downloading and unsupported each get their own message and a real degraded path |
| 2 Input trust | `RoundAgent.instructions` | Menu text is declared untrusted data and only enters prompts. Adjust's direction is one of three fixed sentences — nothing the diner types reaches a prompt |
| 3 Structural | `@Generable` enums | The model cannot invent a category or a basis |
| 4 Grounding | `GroundingGuard`, `OutputValidator` | A claim about a category not on tonight's menu is discarded; so is one too thin to read, or one with volume framing |
| 5 Statistical | `StatisticalGuard` | No claim below minimum *n* |
| 6 Action | `ExclusionValidator`, `StopGuard`, `TriageGuard`, `VerdictGuard`, `ReasonGuard`, `AdjustGuard` | Ternary exclusion; forced stop; forced decline; the move set by the tool's verdict (only a disproved guess changes course); a reason that misstates the verdict never shown as the AI's; the adjusted objective checked against the asked direction |
| 7 Loop | `LoopBudget` | Max rounds, max calls per round, a 45 s wall clock. Every refusal names its reason in the trace |
| 8 Safety | `RoundAgent.retrying(_:)` | One retry on transient generation failures; failures surface as `modelFailure`, never as a decision |

**Several exist because measurement demanded them.** The model chose `stop` 0/3 and `decline` 0/2 times even when handed exhausted capacity — so stopping and declining are computed and forced. A prompt-injection test made the model argue for volume — so the claim is checked before display. The model writes *"the tools say the hypothesis is contradicted"* and then chooses `exploit` — so the move is overridden. **A guardrail overriding on a threshold is legitimate; Swift choosing the next action on a judgement would not be.**

**The exclusion validator is ternary** — *safe · excluded · unknown*. A binary one fails open: *"I could not determine this"* becomes *safe*, the one unrecoverable direction. A dish stays held back until the printed name, a known ingredient list or **the diner, after asking staff**, settles every term. The question goes to the diner, never to the model.

---

## Where each criterion lives

| # | Criterion | Location |
|---|---|---|
| 1 | Human-Centered AI | `TraceLog` and the trace screen (computed vs model), `VerdictBadge` (colour never alone), the guardrails |
| 2 | Custom App Intents | `Intents/` — table-side intents run with `openAppWhenRun = false`; Live Activity intents; the snippet |
| 3 | Siri / Shortcuts / Spotlight | `Intents/Entities.swift` (four `IndexedEntity` types), `KenyangShortcuts`, `SpotlightIndexer` |
| 4 | Foundation Models | `Agent/` |
| 5 | Tool calling | `Tools/AgentTools.swift` |
| 6 | Guardrails | `Guardrails/` (`ClaimGuards`, `DecisionGuards`, `MealGuards`, `LoopBudget`, `ModelAvailability`), `Engine/ExclusionValidator.swift` |
| 7 | Agentic workflows | `Agent/RoundAgent.swift` |

**The rule that decides whether an intent scores:** one that only opens the app is a launcher. Every table-side intent does the work and answers with the app closed.

---

## Running it

Open `Kenyang.xcodeproj` and run the **Kenyang** scheme. **To run on the phone, pick it by its device name under *iOS Device*** — the Simulator is also called "iPhone 17". Apple Intelligence must be available for the agent; without it the app plans without the AI and says so.

**Tests:** `Cmd-U` runs `KenyangTests` (Swift Testing, 39 tests): the skip rule, the order cap, removing a plate, one rating per round, ingredient answers, the stop guard, the avoid-list verdict, a round testing its guess, only a disproved guess changing course, a misstated reason being caught, the per-call deadline, the background round limit, an iOS 27 overflow reaching the overflow path, the tier refusal, the Action Button, the Live Activity phases, and a guard that planning the full menu stays under a second.

**The first launch after a reinstall sometimes stalls before anything appears.** Relaunch.

---

## What has been measured

Every figure is from a logged run.

| | |
|---|---|
| Unit tests, 2026-10-02 | **39 of 39 pass** on the iPhone (iOS 27.0.1) and the iOS 27.0 Simulator (38 of 38 on iOS 26.5 before the iOS 27 test was added). They replaced the in-app battery (30/30 on 2026-09-29) |
| Tool calling | **8/8 tools invoked** by the model, unprompted |
| Falsification tools returning a negative | **3/3** |
| A hypothesis dying, then pivoting | ✅ |
| Context, worst call site | **49% of the 4,096 window** |
| `RoundDecision` decode | ~20% fail first attempt → **5–13% effective** after one retry |
| Round latency, physical iPhone 17 | **~8.4 s** first round, **~3.4 s** after |
| Branch selection, 20 scenarios × 3 runs | **discrimination −5%** — the move does not track the verdict (below) |
| Adjust, the model following the diner's direction on its own | **2 of 6** over two runs — the guard steps in otherwise. Far too few to rank anything |
| Layer 6 against a hand-labelled corpus it never sees | old blacklist **6 leaks**, current **0** |

**The Simulator is not the device.** It ran ~3× slower in early September and faster later; latency comes from the phone only. The iOS 27 Simulator had **no Apple Intelligence assets** on macOS 26; on macOS 27 it runs the model, so it can show *whether* the model answers on 27, never *how fast*.

The model figures above came from measurement harnesses that were removed on 2026-09-30 to keep the app readable; they are recoverable from git history. **They were measured on a 15-dish menu.** The default menu is now 53 dishes, which roughly triples what the menu tool returns; the figures above have not been re-measured on it, but round latency has (4–7 s on the phone, see *Honest status*).

**Context is not the constraint.** Tool definitions are the largest line item; tool results cost 11–28 tokens each. Output is bounded per call site by `GenerationOptions(maximumResponseTokens:)` — **not** by a `.pattern` guide, which compiles and is rejected by the device at runtime, killing every call.

---

## Honest status

### Working

A meal end to end: start from the app, the widget or Siri on the default menu; the avoid-list check; the agent's guess with a pre-registered expectation; the round goal; beam-search planning in **orders**; Adjust through the agent; plate logging with **+ / −**; one rating per dish per round, and skip as a pass on an uneaten dish; capacity accounting that learns from the diner's fullness report; the stop and its question. A home screen with the diner's usual plates, the avoid list and past meals; the launch ring. The trace in plain words with the technical record underneath. Eight App Intents, four `IndexedEntity` types in Spotlight, an interactive snippet, an Action Button intent, a Live Activity that can carry the meal round after round without opening the app, all three Island presentations, a home-screen widget that starts and ends a meal, a Control Center control and a Dining focus filter.

### Seen on hardware — iPhone 17, iOS 26, 2026-10-01

**Rounds of 4–7 s on the 53-dish menu, with tools called.** With Apple Intelligence off, the round is planned without the AI and says so. The feedback loop: a disproved guess changing course with a visible guard override, a backed guess staying, Adjust moving the plan the asked way, four rounds without a stall. **The widget's Start with the app closed → round 1 planned with the AI and on the Live Activity in ~5 s.** Siri by voice with the app closed, Spotlight returning a dish, the Control Center tile.

### Built, not yet exercised on a phone

**Checked in the Simulator only:** the Live Activity's full round (Order these · Good / Skip · Next round · End meal) and its ingredient questions, and both widget states. **Never run:** the snippet redrawing in place · the Action Button and its haptic · the Dining focus · the bright Lock Screen.

### Open defects

1. **The Lock Screen bar can render light-on-light** on the bright Lock Screen. Check on the phone before the next attempt.
2. **The round's plan is in memory** — relaunching mid-meal loses the rating rows until the next round is planned.
3. **Meals started from the widget or Siri skip the avoid-list confirmation.** Dishes the list can't settle are still asked about before the round can be ordered.
4. **Swift 6 `Sendable` warnings** where SwiftData models cross into the tool actor.
5. After a reinstall the widget can show the last meal's snapshot until a new meal starts.

**Deliberately not built:** grill constraints (slots, cook time, plain before marinated) · a thermal budget · OCR menu capture (removed 2026-09-30) · per-category satiety density.

---

## Agency level

**TB, the 20-scenario branch battery, ran three times on 2026-09-18.** It varies the one thing that should drive the branch — what the ratings say about the hypothesis — and reads the move **before** the guards:

| | P(pivot \| contradicted) | P(pivot \| supported) | discrimination |
|---|---|---|---|
| All three runs | 7% (1/14) | 12% (2/17) | **−5%** |

**Branch selection does not read the evidence.** On the two clean runs the model chose `exploit` every time it decoded, 18 for 18 — often right after writing *"the tools say the hypothesis is contradicted"*. So the claim splits, and both halves are measured:

* **Hypothesis composition and the round objective are the model's** — it composes the claim over typed primitives and sets the policy the planner optimises.
* **Branch selection is not agentic.** `VerdictGuard` and `StopGuard` produce the right behaviour; the model does not. Since 2026-10-01 the verdict decides the move outright, and `ReasonGuard` keeps a misstated reason off the screen (the model copied the move's own description in 2 of 5 probe rounds). **The guard layer is the chooser, not a safety net over one** — the honest version, and still a legitimate architecture.

The self-calibration mechanism (`getBasisCalibration`) is built and silenced by its own minimum *n*: **L3 shipped, with an L4 mechanism implemented and refusing to claim on this little data.** Do not round it up — the follow-up question is one sentence long: *how many meals is that?*

---

## Limitations

| Limitation | Consequence |
|---|---|
| **Capacity is inferred, never measured** | A fitted estimate that improves over visits; a coarse default carries meal one |
| **It sees only what you log** | An unlogged plate is invisible |
| **Ingredients are invisible beyond the menu** | Cross-contamination and marinades are unknowable; *unknown* keeps such dishes out of the plan and defers to staff |
| **Flavour fatigue needs many meals** | A population prior until personal data accumulates |
| **The agent chooses what a round is for, not which dishes** | Deliberate — the model never computes — and a real boundary on the agency claim |

**Where it does not work:** self-serve buffets · menus under ~15 items · à la carte · a diner who never rates.

**Permanently out of scope:** nutrition advice · calories · body metrics · food-safety judgements · restaurant discovery or booking · ordering automation.

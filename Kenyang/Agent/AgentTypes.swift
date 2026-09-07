import Foundation
import FoundationModels
import Observation

@Generable
struct ValueHypothesis: Sendable {
    @Guide(description: "Where the value is concentrated at this buffet, in one sentence")
    var claim: String

    var station: StationCategory
    var basis: ValueBasis
    var confidence: ConfidenceBand

    @Guide(description: "The rating you expect from that station, committed before tasting")
    var expectedRating: Rating
}

@Generable
struct RoundIntent: Sendable {
    @Guide(description: "What this round is for, in one sentence")
    var rationale: String

    @Guide(description: """
        How much of this round is spent LEARNING rather than ENJOYING. \
        Learning costs capacity you cannot get back, so it is only worth it early, \
        while there is still capacity to act on what you learn. \
        none — spend everything on dishes already known to be good. \
        quarter — mostly exploit, one small taste of something unknown. \
        half — an even split. \
        most — this round is mainly reconnaissance. \
        Late in the meal, or when the winners are already known, choose none or quarter.
        """)
    var reconShare: ReconShare

    @Guide(description: "Dish names worth spending capacity to learn about. Choose ONLY from the dishes listed in the message.")
    var learnAbout: [String]

    @Guide(description: """
        conservative — stick to safe, known-good choices. \
        balanced — the default. \
        aggressive — accept a poor plate for the chance of a great one.
        """)
    var riskPosture: Posture
}

@Generable
struct RoundDecision: Sendable {
    @Guide(description: "First, state what the tool results actually say. One sentence.")
    var because: String

    @Guide(description: """
        Now choose, consistent with what you just wrote: \
        pivot — the tools say the hypothesis is CONTRADICTED; the value is at a different station. \
        exploit — the tools say the hypothesis is SUPPORTED; spend the remaining capacity on those winners.
        """)
    var move: RoundMove
}

@Generable
struct StationReading: Sendable {
    @Guide(description: "The station this dish belongs to, or unknown if the name does not make it clear")
    var station: StationCategory
    var confidence: ConfidenceBand
}

enum TraceKind: String, Sendable {
    case hypothesis, intent, toolCall, verdict, decision, guardrail, plan, stop, decline
    case modelFailure
}

struct TraceEntry: Identifiable, Sendable {
    let id = UUID()
    let at: Date
    let kind: TraceKind
    let title: String
    let detail: String
    let isDeterministic: Bool

    init(kind: TraceKind, title: String, detail: String, isDeterministic: Bool) {
        self.at = .now
        self.kind = kind
        self.title = title
        self.detail = detail
        self.isDeterministic = isDeterministic
    }
}

@MainActor
@Observable
final class TraceLog {
    private(set) var entries: [TraceEntry] = []

    func record(_ entry: TraceEntry) { entries.append(entry) }

    func record(kind: TraceKind, title: String, detail: String, deterministic: Bool) {
        entries.append(TraceEntry(kind: kind, title: title, detail: detail, isDeterministic: deterministic))
    }

    func clear() { entries.removeAll() }

    var pathSignature: String {
        entries.filter { $0.kind == .decision || $0.kind == .stop || $0.kind == .decline }
            .map(\.title)
            .joined(separator: "→")
    }
}

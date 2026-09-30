import Foundation

/// Bounds the agent: rounds per meal, model calls per round, and seconds per round.
struct LoopBudget {
    enum Refusal: String, Sendable {
        case roundsExhausted  = "the round budget is spent"
        case callsExhausted   = "the call budget for this round is spent"
        case wallClockExpired = "this round passed its wall-clock limit"
    }

    var maxRounds = 6
    var callsPerRound = 6
    /// Clears a normal device round with one retry (~18 s) with room to spare.
    var secondsPerRound: TimeInterval = 45

    private(set) var roundsUsed = 0
    private(set) var callsThisRound = 0
    private var roundStartedAt = Date.now

    mutating func beginRound() {
        roundsUsed += 1
        callsThisRound = 0
        roundStartedAt = .now
    }

    /// Adjust comes after the diner has read the plan, so the clock restarts; the call
    /// count carries over.
    mutating func restartClock() {
        roundStartedAt = .now
    }

    mutating func consumeCall(now: Date = .now) -> Refusal? {
        if roundsUsed > maxRounds { return .roundsExhausted }
        if callsThisRound >= callsPerRound { return .callsExhausted }
        if now.timeIntervalSince(roundStartedAt) > secondsPerRound { return .wallClockExpired }
        callsThisRound += 1
        return nil
    }

    var spentDescription: String {
        "round \(roundsUsed)/\(maxRounds), call \(callsThisRound)/\(callsPerRound)"
    }
}

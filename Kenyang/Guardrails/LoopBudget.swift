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

    var secondsLeft: TimeInterval {
        max(0, secondsPerRound - Date.now.timeIntervalSince(roundStartedAt))
    }
}

struct DeadlinePassed: Error, CustomStringConvertible {
    var description: String { "The AI took longer than the round allows" }
}

/// The call's answer, or `DeadlinePassed` once the deadline goes by, without waiting for
/// the call to notice it was cancelled: the round limit alone only refuses the next call,
/// and one call hung for over three minutes in the Simulator.
@MainActor
func withDeadline<T: Sendable>(seconds: TimeInterval,
                               _ call: @escaping @MainActor () async throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
        var isSettled = false
        var work: Task<Void, Never>?
        var timer: Task<Void, Never>?
        let settle = { (result: Result<T, Error>) in
            guard !isSettled else { return }
            isSettled = true
            work?.cancel()
            timer?.cancel()
            continuation.resume(with: result)
        }
        work = Task { @MainActor in
            do { settle(.success(try await call())) } catch { settle(.failure(error)) }
        }
        timer = Task { @MainActor in
            guard (try? await Task.sleep(for: .seconds(seconds))) != nil else { return }
            settle(.failure(DeadlinePassed()))
        }
    }
}

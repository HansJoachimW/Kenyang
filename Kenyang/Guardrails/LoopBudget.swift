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
    static let foregroundSeconds: TimeInterval = 45
    /// A round started from the widget or the Live Activity runs in the background, and
    /// iOS suspended one at ~30 s, leaving the Live Activity on "Planning…". It gives up on
    /// the AI in time for Kenyang's own plan to reach the screen.
    static let backgroundSeconds: TimeInterval = 20
    private(set) var secondsPerRound = LoopBudget.foregroundSeconds

    private(set) var roundsUsed = 0
    private(set) var callsThisRound = 0
    private var roundStartedAt = Date.now

    mutating func beginRound(within seconds: TimeInterval) {
        roundsUsed += 1
        callsThisRound = 0
        roundStartedAt = .now
        secondsPerRound = seconds
    }

    /// Adjust comes after the diner has read the plan, so the clock restarts; the call
    /// count carries over.
    mutating func restartClock(within seconds: TimeInterval) {
        roundStartedAt = .now
        secondsPerRound = seconds
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

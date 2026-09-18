import Foundation
import Observation

/// What the wait screen reads.
///
/// The design's argument: one indeterminate bar would be a lie, because the first stage
/// is up to twenty times the second. So each stage is named, asks its own question, and
/// reports its own measured ceiling. Three things move and nothing else — a tool line
/// appearing when it returns, a stage collapsing to one completed line, and the next
/// stage's question replacing the last.
@MainActor
@Observable
final class AgentProgress {

    enum Stage: String, CaseIterable, Sendable {
        case hypothesise, setIntent, decide

        var label: String {
            switch self {
            case .hypothesise: "HYPOTHESISE"
            case .setIntent:   "SET INTENT"
            case .decide:      "DECIDE"
            }
        }

        /// The stage states its own question rather than describing itself. A diner who
        /// reads only this line still knows what the app is doing for them.
        var question: String {
            switch self {
            case .hypothesise: "Where is the value tonight?"
            case .setIntent:   "What is this round for?"
            case .decide:      "Does the hypothesis still hold?"
            }
        }

        /// Measured on a physical iPhone 17. The Simulator figures the design was drawn
        /// against — 9.6–30.1 s for `hypothesise` — ran ~3× slow and are retired.
        var ceiling: String {
            switch self {
            case .hypothesise: "up to 10 s"
            case .setIntent:   "~1 s"
            case .decide:      "~3 s"
            }
        }
    }

    struct Completed: Identifiable, Sendable {
        let id = UUID()
        let stage: Stage
        let seconds: Double
    }

    private(set) var current: Stage?
    private(set) var completed: [Completed] = []
    /// Tool lines in the order they returned, so the list is a record of what was asked
    /// rather than a menu of what might be.
    private(set) var toolLines: [String] = []

    private var startedAt: Date?

    var stageNumber: Int { completed.count + 1 }
    var stageTotal: Int { Stage.allCases.count }

    func begin(_ stage: Stage) {
        current = stage
        startedAt = .now
        toolLines = []
    }

    func note(tool: String) {
        guard !toolLines.contains(tool) else { return }
        toolLines.append(tool)
    }

    /// A refusal is worth showing: `getBasisCalibration → insufficient` is the app
    /// declining to claim something, which is the opposite of a failure.
    func note(tool: String, result: String) {
        let line = result.isEmpty ? tool : "\(tool) → \(result)"
        guard !toolLines.contains(line) else { return }
        toolLines.removeAll { $0 == tool }
        toolLines.append(line)
    }

    func finish(_ stage: Stage) {
        let elapsed = startedAt.map { Date.now.timeIntervalSince($0) } ?? 0
        completed.append(Completed(stage: stage, seconds: elapsed))
        current = nil
        startedAt = nil
    }

    func reset() {
        current = nil
        completed = []
        toolLines = []
        startedAt = nil
    }
}

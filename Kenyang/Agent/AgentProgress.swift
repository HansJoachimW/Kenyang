import Foundation
import Observation

/// What the wait screen shows while the agent works: each stage by name, and each tool
/// as it returns.
@MainActor
@Observable
final class AgentProgress {
    enum Stage: CaseIterable, Sendable {
        case hypothesise, setIntent, decide

        var label: String {
            switch self {
            case .hypothesise: "GUESSING"
            case .setIntent:   "SETTING A GOAL"
            case .decide:      "CHECKING"
            }
        }

        var question: String {
            switch self {
            case .hypothesise: "Where's the best food tonight?"
            case .setIntent:   "What is this round for?"
            case .decide:      "Did the guess hold up?"
            }
        }

        /// Measured on an iPhone 17.
        var typicalDuration: String {
            switch self {
            case .hypothesise: "up to 10 s"
            case .setIntent:   "~1 s"
            case .decide:      "~3 s"
            }
        }
    }

    struct CompletedStage: Identifiable, Sendable {
        let id = UUID()
        let stage: Stage
        let seconds: Double
    }

    struct ToolCheck: Hashable, Sendable {
        let tool: String
        let result: String

        var isRefusal: Bool { result == "insufficient" }

        var summary: String { "\(action): \(outcome)" }

        private var action: String {
            switch tool {
            case "getSpread":            "Read the menu"
            case "getPosterior":         "Checked your ratings"
            case "evaluateHypothesis":   "Tested the guess"
            case "checkCapacityModel":   "Checked how full you said you are"
            case "getRemainingCapacity": "Checked room left"
            case "getBasisCalibration":  "Checked past guesses"
            case "getConstraints":       "Checked your avoid list"
            case "getVisitHistory":      "Looked at past visits"
            default:                     tool
            }
        }

        private var outcome: String {
            switch result {
            case "insufficient":    "not enough ratings yet"
            case "supported":       "it held up"
            case "contradicted":    "it didn't hold up"
            case "consistent":      "as expected"
            case "overestimating":  "fuller than expected"
            case "underestimating": "more room than expected"
            case "none set":        "nothing to avoid"
            case "no history":      "first visit"
            default:
                result.hasPrefix("n=") ? "\(result.dropFirst(2)) so far"
                    : result.replacingOccurrences(of: " items", with: " dishes")
            }
        }
    }

    private(set) var current: Stage?
    private(set) var completed: [CompletedStage] = []
    private(set) var checks: [ToolCheck] = []
    private var startedAt: Date?

    var stageNumber: Int { completed.count + 1 }
    var stageCount: Int { Stage.allCases.count }

    func begin(_ stage: Stage) {
        current = stage
        startedAt = .now
        checks = []
    }

    func note(tool: String, result: String) {
        checks.removeAll { $0.tool == tool }
        checks.append(ToolCheck(tool: tool, result: result))
    }

    func finish(_ stage: Stage) {
        let seconds = startedAt.map { Date.now.timeIntervalSince($0) } ?? 0
        completed.append(CompletedStage(stage: stage, seconds: seconds))
        current = nil
        startedAt = nil
    }

    func reset() {
        current = nil
        completed = []
        checks = []
        startedAt = nil
    }
}

import Foundation
import FoundationModels

/// What the tools read during one agent run, and which of them the AI called.
actor ToolContext {
    static let shared = ToolContext()

    private(set) var input = AgentInput.empty
    private(set) var invoked: Set<String> = []
    private var observer: (@Sendable (String, String) -> Void)?

    var sightings: [DishSighting] { input.sightings }
    var events: [TasteEvent] { input.events }
    var capacity: CapacityState { input.capacity }
    var minutesRemaining: Int? { input.minutesRemaining }
    var exclusions: [String] { input.exclusions }
    var basisRecords: [BasisRecord] { input.basisRecords }
    var fullnessReadings: [FullnessReading] { input.fullnessReadings }
    var calledTools: [String] { invoked.sorted() }

    func load(_ input: AgentInput) {
        self.input = input
        invoked = []
    }

    /// Streams each result to the wait screen as it returns.
    func observe(_ observer: (@Sendable (String, String) -> Void)?) {
        self.observer = observer
    }

    func note(_ name: String) { invoked.insert(name) }

    func note(_ name: String, result: String) {
        invoked.insert(name)
        observer?(name, result)
    }
}

struct GetSpreadTool: Tool {
    let name = "getSpread"
    let description = "Lists the items on the menu with their category, the section they are printed under, and their price tier."

    @Generable struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        await ToolContext.shared.note(name)
        let sightings = await ToolContext.shared.sightings
        guard !sightings.isEmpty else {
            await ToolContext.shared.note(name, result: "no dishes")
            return "no dishes recorded"
        }
        await ToolContext.shared.note(name, result: "\(sightings.count) items")
        return sightings.map { s in
            var line = "\(s.name) [\(s.category.rawValue)]"
            if s.tierRank > 0 { line += " TIER \(s.tierRank + 1)" }
            if !s.printedCategory.isEmpty { line += " (\(s.printedCategory))" }
            return line
        }.joined(separator: "; ")
    }
}

struct GetPosteriorTool: Tool {
    let name = "getPosterior"
    let description = "Returns the current value estimate for one menu category, with its sample count. Low sample counts must not be treated as reliable."

    @Generable struct Arguments {
        @Guide(description: "The menu category to look up")
        var category: MenuCategory
    }

    func call(arguments: Arguments) async throws -> String {
        await ToolContext.shared.note(name)
        let events = await ToolContext.shared.events
        let p = ValueEngine.categoryPosterior(arguments.category, events: events)
        guard p.isTrustworthy else {
            await ToolContext.shared.note(name, result: "insufficient")
            return "\(arguments.category.rawValue): insufficient data (n=\(p.sampleCount))"
        }
        await ToolContext.shared.note(name, result: "n=\(p.sampleCount)")
        return "\(arguments.category.rawValue): mean=\(String(format: "%.2f", p.mean)) n=\(p.sampleCount)"
    }
}

struct EvaluateHypothesisTool: Tool {
    let name = "evaluateHypothesis"
    let description = "Tests the current value hypothesis against the ratings recorded so far. Returns supported, contradicted, or insufficient. This is the only authority on whether the hypothesis holds — never judge it yourself."

    @Generable struct Arguments {
        @Guide(description: "The menu category the hypothesis claims the value is concentrated in")
        var category: MenuCategory
        @Guide(description: "The rating that was expected from that category")
        var expectedRating: Rating
    }

    func call(arguments: Arguments) async throws -> String {
        await ToolContext.shared.note(name)
        let events = await ToolContext.shared.events
        let p = ValueEngine.categoryPosterior(arguments.category, events: events)
        let verdict = ValueEngine.verdict(p, expecting: arguments.expectedRating)
        guard verdict != .insufficient else {
            await ToolContext.shared.note(name, result: "insufficient")
            return "evaluateHypothesis(\(arguments.category.rawValue)) = insufficient (n=\(p.sampleCount))"
        }
        let expected = arguments.expectedRating.score
        await ToolContext.shared.note(name, result: verdict.rawValue)
        return "evaluateHypothesis(\(arguments.category.rawValue)) = \(verdict.rawValue) (observed \(String(format: "%.2f", p.mean)) vs expected \(String(format: "%.2f", expected)), n=\(p.sampleCount))"
    }
}

struct CheckCapacityModelTool: Tool {
    let name = "checkCapacityModel"
    let description = "Falsifies the capacity ESTIMATE itself by comparing what the app predicted against the fullness the diner reported. Returns consistent, overestimating, underestimating, or insufficient. Call this when deciding whether the remaining capacity can still be trusted — it answers a different question from getRemainingCapacity, which only reports the current number."

    @Generable struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        await ToolContext.shared.note(name)
        let capacity = await ToolContext.shared.capacity
        let readings = await ToolContext.shared.fullnessReadings
        guard let latest = readings.sorted(by: { $0.at < $1.at }).last else {
            await ToolContext.shared.note(name, result: "insufficient")
            return "checkCapacityModel = insufficient (no fullness reading this meal; the capacity estimate is unverified)"
        }
        let predicted = CapacityEngine.predictedFullness(
            CapacityState(maxSatiety: capacity.declaredMax, spent: latest.cumulativeSatiety))
        let verdict = CapacityEngine.verdict(declaredMax: capacity.declaredMax, readings: readings)
        await ToolContext.shared.note(name, result: verdict.rawValue)
        return "checkCapacityModel = \(verdict.rawValue) (predicted fullness \(predicted)/5, diner reported \(latest.value)/5)"
    }
}

struct GetRemainingCapacityTool: Tool {
    let name = "getRemainingCapacity"
    let description = "Returns how much stomach capacity and seating time the diner has left."

    @Generable struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        await ToolContext.shared.note(name)
        let capacity = await ToolContext.shared.capacity
        let minutes = await ToolContext.shared.minutesRemaining
        let time = minutes.map { "\($0) minutes of seating left" } ?? "no seating limit"
        await ToolContext.shared.note(name, result: "\(String(format: "%.1f", capacity.plateEstimate)) plates")
        return "about \(String(format: "%.1f", capacity.plateEstimate)) plates left; \(time)"
    }
}

struct GetBasisCalibrationTool: Tool {
    let name = "getBasisCalibration"
    let description = "Reports how well each kind of reasoning has predicted ratings in the past. Returns insufficient when there is not enough history to trust any of them."

    @Generable struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        await ToolContext.shared.note(name)
        let records = await ToolContext.shared.basisRecords
        let minimum = 8
        guard records.count >= minimum else {
            await ToolContext.shared.note(name, result: "insufficient")
            return "getBasisCalibration = insufficient (n=\(records.count), need \(minimum)). Use population priors."
        }
        let grouped = Dictionary(grouping: records, by: \.basis)
        let lines = grouped.map { basis, rows -> String in
            let err = rows.reduce(0.0) { $0 + $1.absoluteError } / Double(rows.count)
            return "\(basis.rawValue): n=\(rows.count) meanError=\(String(format: "%.2f", err))"
        }
        await ToolContext.shared.note(name, result: "n=\(records.count)")
        return lines.joined(separator: "; ")
    }
}

struct GetConstraintsTool: Tool {
    let name = "getConstraints"
    let description = "Returns the diner's exclusion list as ingredients only. The reason an item is on the list is never stored and never returned."

    @Generable struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        await ToolContext.shared.note(name)
        let exclusions = await ToolContext.shared.exclusions
        guard !exclusions.isEmpty else {
            await ToolContext.shared.note(name, result: "none set")
            return "no exclusions set"
        }
        await ToolContext.shared.note(name, result: "\(exclusions.count) to avoid")
        return "must avoid: \(exclusions.joined(separator: ", "))"
    }
}

struct GetVisitHistoryTool: Tool {
    let name = "getVisitHistory"
    let description = "Returns what is already known about this restaurant from previous visits."

    @Generable struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        await ToolContext.shared.note(name)
        let events = await ToolContext.shared.events
        guard !events.isEmpty else {
            await ToolContext.shared.note(name, result: "no history")
            return "no previous visits recorded"
        }
        await ToolContext.shared.note(name, result: "\(events.count) rated")
        let byCategory = Dictionary(grouping: events, by: \.category)
        return byCategory.map { category, rows in
            let mean = rows.reduce(0.0) { $0 + $1.rating.score } / Double(rows.count)
            return "\(category.rawValue): \(String(format: "%.2f", mean)) over \(rows.count)"
        }.joined(separator: "; ")
    }
}

enum AgentToolbox {
    static var readTools: [any Tool] {
        [
            GetSpreadTool(),
            GetPosteriorTool(),
            EvaluateHypothesisTool(),
            CheckCapacityModelTool(),
            GetRemainingCapacityTool(),
            GetBasisCalibrationTool(),
            GetConstraintsTool(),
            GetVisitHistoryTool()
        ]
    }
}

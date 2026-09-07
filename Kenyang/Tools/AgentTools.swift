import Foundation
import FoundationModels

actor ToolContext {
    static let shared = ToolContext()

    private(set) var sightings: [DishSighting] = []
    private(set) var events: [TasteEvent] = []
    private(set) var capacity = CapacityState(maxSatiety: 9, spent: 0)
    private(set) var minutesRemaining: Int?
    private(set) var exclusions: [String] = []
    private(set) var basisRecords: [BasisRecord] = []
    private(set) var fullnessReadings: [FullnessReading] = []
    private(set) var hypothesisStation: StationCategory = .unknown
    private(set) var invoked: Set<String> = []

    func load(sightings: [DishSighting],
              events: [TasteEvent],
              capacity: CapacityState,
              minutesRemaining: Int?,
              exclusions: [String],
              basisRecords: [BasisRecord],
              fullnessReadings: [FullnessReading],
              hypothesisStation: StationCategory) {
        self.sightings = sightings
        self.events = events
        self.capacity = capacity
        self.minutesRemaining = minutesRemaining
        self.exclusions = exclusions
        self.basisRecords = basisRecords
        self.fullnessReadings = fullnessReadings
        self.hypothesisStation = hypothesisStation
    }

    func resetInvocations() { invoked = [] }
    func note(_ name: String) { invoked.insert(name) }
    var invocationList: [String] { invoked.sorted() }
}

struct GetSpreadTool: Tool {
    let name = "getSpread"
    let description = "Lists the dishes available at this buffet with their station and whether the house is rationing them."

    @Generable struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        await ToolContext.shared.note(name)
        let sightings = await ToolContext.shared.sightings
        guard !sightings.isEmpty else { return "no dishes recorded" }
        return sightings.map { s in
            var line = "\(s.name) [\(s.station.rawValue)]"
            if s.isRationed { line += " RATIONED" }
            if s.isMadeToOrder { line += " made-to-order" }
            return line
        }.joined(separator: "; ")
    }
}

struct GetPosteriorTool: Tool {
    let name = "getPosterior"
    let description = "Returns the current value estimate for one station, with its sample count. Low sample counts must not be treated as reliable."

    @Generable struct Arguments {
        @Guide(description: "The station to look up")
        var station: StationCategory
    }

    func call(arguments: Arguments) async throws -> String {
        await ToolContext.shared.note(name)
        let events = await ToolContext.shared.events
        let p = ValueEngine.stationPosterior(arguments.station, events: events)
        guard StatisticalGuard.canClaim(p) else {
            return "\(arguments.station.rawValue): insufficient data (n=\(p.sampleCount))"
        }
        return "\(arguments.station.rawValue): mean=\(String(format: "%.2f", p.mean)) n=\(p.sampleCount)"
    }
}

struct EvaluateHypothesisTool: Tool {
    let name = "evaluateHypothesis"
    let description = "Tests the current value hypothesis against the ratings recorded so far. Returns supported, contradicted, or insufficient. This is the only authority on whether the hypothesis holds — never judge it yourself."

    @Generable struct Arguments {
        @Guide(description: "The station the hypothesis claims the value is concentrated in")
        var station: StationCategory
        @Guide(description: "The rating that was expected from that station")
        var expectedRating: Rating
    }

    func call(arguments: Arguments) async throws -> String {
        await ToolContext.shared.note(name)
        let events = await ToolContext.shared.events
        let p = ValueEngine.stationPosterior(arguments.station, events: events)
        guard p.sampleCount >= ValueEngine.minimumSamples else {
            return "evaluateHypothesis(\(arguments.station.rawValue)) = insufficient (n=\(p.sampleCount))"
        }
        let expected = arguments.expectedRating.score
        let verdict: HypothesisVerdict = p.mean >= expected - 0.25 ? .supported : .contradicted
        return "evaluateHypothesis(\(arguments.station.rawValue)) = \(verdict.rawValue) (observed \(String(format: "%.2f", p.mean)) vs expected \(String(format: "%.2f", expected)), n=\(p.sampleCount))"
    }
}

struct CheckCapacityModelTool: Tool {
    let name = "checkCapacityModel"
    let description = "Falsifies the capacity ESTIMATE itself by comparing what the app predicted against the fullness the diner reported. Returns consistent, overestimating, underestimating, or insufficient. Call this when deciding whether the remaining budget can still be trusted — it answers a different question from getRemainingCapacity, which only reports the current number."

    @Generable struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        await ToolContext.shared.note(name)
        let capacity = await ToolContext.shared.capacity
        let readings = await ToolContext.shared.fullnessReadings
        guard let latest = readings.sorted(by: { $0.at < $1.at }).last else {
            return "checkCapacityModel = insufficient (no fullness reading this meal; the budget is an unverified estimate)"
        }
        let predicted = CapacityEngine.predictedFullness(
            CapacityState(maxSatiety: capacity.maxSatiety, spent: latest.cumulativeSatiety))
        let delta = latest.value - predicted
        let verdict: CapacityVerdict = delta >= 2 ? .overestimating
            : delta <= -2 ? .underestimating : .consistent
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
            return "getBasisCalibration = insufficient (n=\(records.count), need \(minimum)). Use population priors."
        }
        let grouped = Dictionary(grouping: records, by: \.basis)
        let lines = grouped.map { basis, rows -> String in
            let err = rows.reduce(0.0) { $0 + $1.absoluteError } / Double(rows.count)
            return "\(basis.rawValue): n=\(rows.count) meanError=\(String(format: "%.2f", err))"
        }
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
        guard !exclusions.isEmpty else { return "no exclusions set" }
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
        guard !events.isEmpty else { return "no previous visits recorded" }
        let byStation = Dictionary(grouping: events, by: \.station)
        return byStation.map { station, rows in
            let mean = rows.reduce(0.0) { $0 + $1.rating.score } / Double(rows.count)
            return "\(station.rawValue): \(String(format: "%.2f", mean)) over \(rows.count)"
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

    static let allNames = [
        "getSpread", "getPosterior", "evaluateHypothesis", "checkCapacityModel",
        "getRemainingCapacity", "getBasisCalibration", "getConstraints", "getVisitHistory"
    ]
}

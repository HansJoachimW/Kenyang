import Foundation
import Observation

/// Plans, adjusts and re-plans rounds for the meal in progress, whichever surface asked.
@MainActor
@Observable
final class RoundCoordinator {
    let session: MealSession
    let progress = AgentProgress()
    private(set) var isPlanning = false
    private(set) var claimRejection: ClaimRejection?

    @ObservationIgnored private var agent: RoundAgent?
    @ObservationIgnored private weak var agentVisit: Visit?
    @ObservationIgnored private var planningTask: Task<AgentOutcome?, Never>?

    init(session: MealSession) {
        self.session = session
    }

    /// Plans the next round and proposes it. Returns the agent's outcome, so a screen can
    /// show a stop or a decline; nil when there is no meal or planning was cancelled.
    @discardableResult
    func planRound(advancing: Bool,
                   within seconds: TimeInterval = LoopBudget.foregroundSeconds) async -> AgentOutcome? {
        if let planningTask { return await planningTask.value }
        guard session.visit != nil else { return nil }

        session.beginRound(advancing: advancing)
        progress.reset()
        claimRejection = nil
        isPlanning = true
        defer {
            isPlanning = false
            planningTask = nil
        }

        let task = Task { await runAgent(within: seconds) }
        planningTask = task
        return await task.value
    }

    func adjustRound(toward direction: AdjustDirection?,
                     within seconds: TimeInterval = LoopBudget.foregroundSeconds) async {
        guard var input = session.agentInput() else { return }
        input.secondsForRound = seconds
        isPlanning = true
        defer { isPlanning = false }
        session.trace.record(.plan, "adjust requested", "The diner rejected the plan — \(direction?.label ?? "no reason given").")
        let (plan, adjusted) = await currentAgent().adjust(input,
                                                           hypothesis: session.hypothesis,
                                                           rejected: session.intent ?? .balanced,
                                                           direction: direction)
        session.propose(plan, intent: adjusted)
    }

    /// Skips the AI and plans from typical ratings and the room left.
    func planWithoutAgent(note: String = "Planned without the AI because you skipped it.") {
        planningTask?.cancel()
        planningTask = nil
        isPlanning = false
        guard let input = session.agentInput() else { return }
        session.trace.record(.guardrail, "skipped to priors", "Planned from typical ratings instead of the AI's guess.")
        session.propose(planUnder(.balanced, input: input), note: note)
    }

    func answer(_ ingredient: String, contains: Bool, for dishName: String) {
        let emptied = session.answer(ingredient, contains: contains, for: dishName)
        guard emptied, let input = session.agentInput() else { return }
        session.trace.record(.plan, "re-planned", "Every planned dish was ruled out, so the round was planned again under the same objective.")
        let objective = RoundAgent.objective(from: session.intent, events: input.events,
                                             testing: session.hypothesis?.category)
        session.propose(planUnder(objective, input: input))
    }

    // MARK: -

    private func runAgent(within seconds: TimeInterval) async -> AgentOutcome? {
        guard var input = session.agentInput() else { return nil }
        input.secondsForRound = seconds
        let agent = currentAgent()
        await ToolContext.shared.observe { [progress] tool, result in
            Task { @MainActor in progress.note(tool: tool, result: result) }
        }
        let outcome = await agent.run(input)
        await ToolContext.shared.observe(nil)
        guard !Task.isCancelled else { return nil }

        claimRejection = agent.claimRejection
        switch outcome {
        case .planned(let plan, let hypothesis, let intent):
            session.propose(plan, hypothesis: hypothesis, intent: intent)
        case .degraded(let plan, let message):
            session.propose(plan, note: message)
        case .stopped(_, let message), .declined(let message):
            session.show(note: message)
        }
        return outcome
    }

    private func currentAgent() -> RoundAgent {
        if let agent, agentVisit === session.visit { return agent }
        let fresh = RoundAgent(trace: session.trace, progress: progress)
        agent = fresh
        agentVisit = session.visit
        return fresh
    }

    private func planUnder(_ objective: PlannerObjective, input: AgentInput) -> RoundPlan {
        RoundPlanner.plan(objective: objective,
                          candidates: input.sightings,
                          events: input.events,
                          capacity: input.capacity,
                          exclusions: input.exclusions)
    }
}

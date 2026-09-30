import ActivityKit
import Foundation

/// Mirrors the meal onto the Live Activity and the home-screen widget. It never drives
/// the meal; every change reaches it through `MealSession.publish()`.
@MainActor
final class LiveActivityController: MealDisplay {
    static let shared = LiveActivityController()

    private init() {}

    /// Looked up rather than remembered, so an activity started before a relaunch can
    /// still be updated and ended.
    private var activity: Activity<RoundActivityAttributes>? {
        Activity<RoundActivityAttributes>.activities.first {
            $0.activityState == .active || $0.activityState == .stale
        }
    }

    func show(_ session: MealSession) {
        guard let visit = session.visit else { return }
        let content = Self.content(for: session, visit: visit)
        if let activity {
            Task { await activity.update(ActivityContent(state: content, staleDate: nil)) }
        } else if ActivityAuthorizationInfo().areActivitiesEnabled {
            _ = try? Activity.request(attributes: RoundActivityAttributes(venueName: visit.venueName),
                                      content: ActivityContent(state: content, staleDate: nil))
        }
        publishSnapshot(of: visit, content: content)
    }

    func clear(endedVisit visit: Visit, round: Int) {
        endAllActivities()
        let capacity = CapacityEngine.state(for: visit)
        publishSnapshot(of: visit, content: .init(phase: .timeToStop,
                                                  fractionRemaining: capacity.fractionRemaining,
                                                  plateEstimate: capacity.plateEstimate,
                                                  round: round))
    }

    /// Dismissed immediately; the default policy would leave an ended meal on the Lock
    /// Screen for up to four hours.
    func endAllActivities() {
        for activity in Activity<RoundActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    // MARK: - What to show

    static func content(for session: MealSession, visit: Visit) -> RoundActivityAttributes.ContentState {
        let capacity = CapacityEngine.state(for: visit)
        let stopReason = StopGuard.reason(capacity: capacity, minutesRemaining: visit.minutesRemaining)
        let hasSuggestion = !session.isEating && session.plan.map { !$0.isEmpty } == true
        let next = session.isEating ? session.nextDish()?.item.dishName : nil
        let phase = phase(isStopping: stopReason != .none,
                          hasSuggestion: hasSuggestion,
                          isEating: session.isEating,
                          hasNextDish: next != nil)

        var content = RoundActivityAttributes.ContentState(
            phase: phase,
            fractionRemaining: capacity.fractionRemaining,
            plateEstimate: capacity.plateEstimate,
            minutesToLastOrder: visit.minutesRemaining.flatMap { $0 <= StopGuard.lastOrderMinutes ? $0 : nil },
            round: session.round,
            nextDish: next,
            message: phase == .timeToStop ? StopGuard.message(for: stopReason) : session.note)
        if phase == .suggested, let plan = session.plan {
            content.suggestion = plan.items.map(\.orderLabel)
            content.question = session.firstOpenQuestion().map { .init(dish: $0.dish, ingredient: $0.ingredient) }
        }
        return content
    }

    static func phase(isStopping: Bool, hasSuggestion: Bool, isEating: Bool,
                      hasNextDish: Bool) -> RoundActivityAttributes.Phase {
        if isStopping { return .timeToStop }
        if hasSuggestion { return .suggested }
        if isEating { return hasNextDish ? .eating : .roundDone }
        return .planning
    }

    private func publishSnapshot(of visit: Visit, content: RoundActivityAttributes.ContentState) {
        MealSnapshotStore.write(MealSnapshot(venueName: visit.venueName,
                                             fractionRemaining: content.fractionRemaining,
                                             plateEstimate: content.plateEstimate,
                                             round: content.round,
                                             nextDish: content.nextDish,
                                             isActive: visit.isActive,
                                             updatedAt: .now))
    }
}

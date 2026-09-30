import ActivityKit
import Foundation

/// Starts, updates and ends the round's Live Activity.
///
/// The derivation is split out into `state(for:)` so it can be checked without
/// ActivityKit, a device, or a widget extension — the mapping from meal state to what
/// the Island shows is the part that can be wrong, and it is pure.
@MainActor
final class LiveActivityController {
    static let shared = LiveActivityController()

    /// Asked of ActivityKit rather than remembered. A relaunch lost the remembered one
    /// while the activity itself stayed up, so nothing could end it and the next
    /// `syncActivity` started a second.
    private var activity: Activity<RoundActivityAttributes>? {
        Activity<RoundActivityAttributes>.activities.first {
            $0.activityState == .active || $0.activityState == .stale
        }
    }

    private init() {}

    var isRunning: Bool { activity != nil }

    /// `areActivitiesEnabled` is false when the diner has switched Live Activities off
    /// for the app. That is a setting, not an error: the meal carries on and nothing
    /// else in the app depends on the activity existing.
    var isPermitted: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    func start(venue: String, state: RoundActivityAttributes.ContentState) {
        guard isPermitted, activity == nil else { return }
        _ = try? Activity.request(
            attributes: RoundActivityAttributes(venueName: venue),
            content: ActivityContent(state: state, staleDate: nil)
        )
    }

    func update(_ state: RoundActivityAttributes.ContentState) {
        guard let activity else { return }
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    /// Every activity goes, not only the newest, and **immediately**: the activity is
    /// for a meal in progress. `.default` kept an ended meal on the Lock Screen for up
    /// to four hours.
    func end() {
        for activity in Activity<RoundActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    /// The meal is over: take the activity down and tell the widget. Call after
    /// `endVisit`, so the snapshot records `isActive: false`. The widget does not
    /// dismiss itself, and without the snapshot it would keep showing the ended meal.
    func finish(visit: Visit, roundIndex: Int) {
        end()
        let ended = Self.state(phase: .stopGuard,
                               capacity: CapacityEngine.state(for: visit),
                               minutesRemaining: visit.minutesRemaining,
                               roundIndex: roundIndex,
                               nextTarget: nil,
                               message: "Meal ended.")
        publishSnapshot(visit: visit, state: ended)
    }

    /// Recompute from the store alone. The view model owns the richer version; this is
    /// the one a Live Activity button can reach, because a background launch for an
    /// intent has no view model and no scene.
    func refresh(visit: Visit, store: KenyangStore) {
        let capacity = CapacityEngine.state(for: visit)
        let state = Self.state(
            phase: Self.phase(capacity: capacity,
                              minutesRemaining: visit.minutesRemaining,
                              isDegraded: false,
                              isEating: visit.outcome == .running),
            capacity: capacity,
            minutesRemaining: visit.minutesRemaining,
            roundIndex: store.currentRound(in: visit),
            nextTarget: store.lastPlan.flatMap { store.nextUnloggedItem(in: $0, visit: visit)?.item.dishName },
            message: nil
        )
        update(state)
        publishSnapshot(visit: visit, state: state)
    }

    /// The home-screen widget reads a snapshot, not the store — see `MealSnapshot`.
    func publishSnapshot(visit: Visit, state: RoundActivityAttributes.ContentState) {
        MealSnapshotStore.write(
            MealSnapshot(venueName: visit.restaurant?.name ?? "Kenyang",
                         fractionRemaining: state.fractionRemaining,
                         plateEstimate: state.plateEstimate,
                         roundIndex: state.roundIndex,
                         nextTarget: state.nextTarget,
                         isActive: visit.isActive,
                         updatedAt: .now)
        )
    }

    // MARK: - The derivation

    /// Everything the four states and three presentations render from, in one place.
    ///
    /// `nextTarget` is the same "first unlogged item in plan order" rule the Action
    /// Button presses, so the Island names the dish the button would log. If those two
    /// ever disagree the diner is being told one thing and handed another.
    static func state(phase: RoundActivityAttributes.Phase,
                      capacity: CapacityState,
                      minutesRemaining: Int?,
                      roundIndex: Int,
                      nextTarget: String?,
                      message: String?) -> RoundActivityAttributes.ContentState {
        RoundActivityAttributes.ContentState(
            phase: phase,
            fractionRemaining: capacity.fractionRemaining,
            plateEstimate: capacity.plateEstimate,
            // Under fifteen minutes is the last-order threshold StopGuard uses. Above
            // it the countdown is noise the diner can do nothing with, so it is not
            // shown at all rather than shown and ignored.
            minutesToLastOrder: minutesRemaining.flatMap { $0 <= 15 ? $0 : nil },
            roundIndex: roundIndex,
            nextTarget: nextTarget,
            message: message
        )
    }

    /// The phase the meal is actually in, computed rather than passed around, so the
    /// stop guard reaches the Island by the same route it reaches every other surface.
    static func phase(capacity: CapacityState,
                      minutesRemaining: Int?,
                      isDegraded: Bool,
                      isEating: Bool) -> RoundActivityAttributes.Phase {
        if StopGuard.shouldStop(capacity: capacity, minutesRemaining: minutesRemaining) {
            return .stopGuard
        }
        if isDegraded { return .degraded }
        return isEating ? .active : .planning
    }
}

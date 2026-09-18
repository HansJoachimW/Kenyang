import AppIntents
import Foundation
import UIKit

// B3 — the Action Button.
//
//   press → plan.items where logged == false → take the FIRST in plan order
//         → write · haptic ×1 · run StopGuard
//         → second press within 8 s reassigns to next item · haptic ×2
//
// The whole point is the zero-screen path: phone face-down on the table, tongs in the
// other hand. An intent that opens the app is a launcher, not an intent.
//
// **It logs; it never rates.** A blind press cannot know whether the food was any good,
// and writing a guessed rating would put a fabricated value observation into the
// posterior — worse than having none, because nothing downstream can tell the two
// apart. `TasteEvent.isRated` is what keeps the capacity loop and the value loop
// separate, and this intent writes only into the first of them.

struct LogNextItemIntent: AppIntent {
    static var title: LocalizedStringResource = "Log the next item"
    static var description = IntentDescription("Log the next dish in the planned round without opening the app. Press again within eight seconds to correct it.")
    static var openAppWhenRun = false

    /// The window in which a second press means *"no, it was the other one"* rather
    /// than *"and now I have eaten another"*.
    static let reassignWindow: TimeInterval = 8

    @Dependency private var store: KenyangStore

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: Self.press(on: store)))
    }

    /// The whole behaviour, as a pure-ish function of the store, so the battery can run
    /// it without going through the App Intents runtime — `@Dependency` resolves only
    /// inside a real perform flow, and a check that cannot be run is the failure
    /// `TESTS.md` exists to prevent.
    @MainActor
    static func press(on store: KenyangStore) -> String {
        guard let visit = store.activeVisit() else {
            return "No meal in progress. Start a session first."
        }
        guard let plan = store.lastPlan, !plan.isEmpty else {
            return "No round planned yet. Ask for a round first."
        }

        if let pending = store.pendingLog,
           Date.now.timeIntervalSince(pending.at) <= reassignWindow {
            return reassign(from: pending, plan: plan, visit: visit, store: store)
        }
        return logNext(plan: plan, visit: visit, store: store)
    }

    // MARK: - Second press, inside the window

    @MainActor
    private static func reassign(from pending: KenyangStore.PendingLog,
                                 plan: RoundPlan,
                                 visit: Visit,
                                 store: KenyangStore) -> String {
        let nextIndex = pending.itemIndex + 1
        guard nextIndex < plan.items.count else {
            // Nothing left to reassign to. The first log stands rather than being
            // silently dropped — an unlogged plate is a capacity observation lost.
            Haptics.tap(times: 1)
            return "That was the last item in the round, so I have left it as \(pending.event.dishName)."
        }

        let item = plan.items[nextIndex]
        let previous = pending.event.dishName
        store.delete(pending.event)

        let event = store.rate(dishName: item.dishName,
                               category: item.category,
                               rating: nil,
                               portion: item.portion,
                               in: visit,
                               roundIndex: store.currentRound(in: visit))
        store.pendingLog = KenyangStore.PendingLog(event: event, itemIndex: nextIndex, at: .now)
        Haptics.tap(times: 2)

        return stopMessage(visit: visit)
            ?? "Changed \(previous) to \(item.dishName). \(platesLeft(visit))"
    }

    // MARK: - First press

    @MainActor
    private static func logNext(plan: RoundPlan, visit: Visit, store: KenyangStore) -> String {
        guard let next = store.nextUnloggedItem(in: plan, visit: visit) else {
            store.pendingLog = nil
            Haptics.tap(times: 1)
            return "Everything in this round is logged. Ask for another round when you are ready."
        }

        let event = store.rate(dishName: next.item.dishName,
                               category: next.item.category,
                               rating: nil,
                               portion: next.item.portion,
                               in: visit,
                               roundIndex: store.currentRound(in: visit))
        store.pendingLog = KenyangStore.PendingLog(event: event, itemIndex: next.index, at: .now)
        Haptics.tap(times: 1)

        // The design locks this: every log runs the deterministic stop check. The moment
        // the diner is least able to judge whether to stop is the moment they are
        // reaching for the next plate.
        return stopMessage(visit: visit)
            ?? "Logged \(next.item.dishName). \(platesLeft(visit))"
    }

    // MARK: -

    @MainActor
    private static func stopMessage(visit: Visit) -> String? {
        let capacity = CapacityEngine.state(for: visit)
        let reason = StopGuard.reason(capacity: capacity, minutesRemaining: visit.minutesRemaining)
        guard reason != .none else { return nil }
        return StopGuard.message(for: reason)
    }

    @MainActor
    private static func platesLeft(_ visit: Visit) -> String {
        let plates = CapacityEngine.state(for: visit).plateEstimate
        if plates < 0.75 { return "About half a plate left." }
        return "About \(String(format: "%.1f", plates)) plates left."
    }
}

/// One tap for a log, two for a correction — the diner learns which happened without
/// looking, which is the only feedback channel a face-down phone has.
///
/// ⚠️ **Best effort, and unverified with the app closed.** `UIFeedbackGenerator` needs a
/// foreground scene to produce anything; an intent run from the Action Button executes
/// in a background process, where these calls are expected to no-op silently. The
/// dialog is the feedback that is actually guaranteed, and the Action Button renders it
/// in its own HUD. Recorded here rather than claimed, because the haptic is the part of
/// this design that has never been felt on a device.
@MainActor
enum Haptics {
    static func tap(times: Int) {
        guard times > 0, UIApplication.shared.applicationState == .active else { return }
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
        guard times > 1 else { return }
        for step in 1..<times {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12 * Double(step)) {
                generator.impactOccurred()
            }
        }
    }
}

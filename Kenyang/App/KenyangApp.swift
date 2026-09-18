import AppIntents
import SwiftData
import SwiftUI

@main
struct KenyangApp: App {
    private let store: KenyangStore

    init() {
        let container = KenyangStore.makeContainer()
        let store = KenyangStore(container: container)
        self.store = store
        AppDependencyManager.shared.add(dependency: store)

        // A Live Activity button's `perform()` runs in THIS process, so the handler has
        // to be registered before any of them can fire. `init` is the only place that
        // is true for a background launch, where there is no scene and no `.task`.
        MainActor.assumeIsolated {
            ActivityBridge.shared.register { command in
                Self.handle(command, store: store)
            }
        }
    }

    @MainActor
    private static func handle(_ command: ActivityCommand, store: KenyangStore) {
        guard let visit = store.activeVisit() else { return }
        switch command {
        case .stop:
            // A one-tap Stop cannot know WHY the meal ended, and only a `fullness`
            // ending measures capacity. Recording `.unknown` keeps it an honest lower
            // bound instead of feeding the fit an observation nobody made.
            store.endVisit(visit, outcome: .stopped, ending: .unknown)
            LiveActivityController.shared.end(
                LiveActivityController.state(phase: .stopGuard,
                                             capacity: CapacityEngine.state(for: visit),
                                             minutesRemaining: visit.minutesRemaining,
                                             roundIndex: store.currentRound(in: visit),
                                             nextTarget: nil,
                                             message: "Meal ended.")
            )
        case .rateGood, .rateSkip:
            // Unlike the Action Button this rates, because the Island names the dish
            // directly above the buttons — the diner can see what they are answering.
            guard let plan = store.lastPlan,
                  let next = store.nextUnloggedItem(in: plan, visit: visit) else { return }
            store.rate(dishName: next.item.dishName,
                       category: next.item.category,
                       rating: command == .rateGood ? .good : .skip,
                       portion: next.item.portion,
                       in: visit,
                       roundIndex: store.currentRound(in: visit))
            LiveActivityController.shared.refresh(visit: visit, store: store)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.kenyangStore, store)
                .modelContainer(store.container)
                .task {
                    // TESTS.md T50/T51/T52 harness — see Verification/TokenAudit.swift
                    await SpotlightIndexer.reindex(store)

                    let args = CommandLine.arguments
                    let all = args.contains("--run-all")

                    // T53 — the capture pipeline against a real menu file. Takes a path,
                    // so it is deliberately not part of --run-all.
                    if let flag = args.firstIndex(of: "--capture-probe"), flag + 1 < args.count {
                        await CaptureProbe.run(path: args[flag + 1])
                        exit(0)
                    }

                    if all || args.contains("--verify") {
                        let runner = VerificationRunner(store: store)
                        await runner.runAll()
                        if !all { exit(0) }
                    }
                    if all || args.contains("--token-audit") {
                        await TokenAudit.run()
                        if !all { exit(0) }
                    }
                    if all || args.contains("--stance-probe") {
                        await StanceProbe.run()
                        if !all { exit(0) }
                    }
                    if all || args.contains("--growth-audit") {
                        await GrowthAudit.run()
                        if !all { exit(0) }
                    }
                    if all || args.contains("--schema-probe") {
                        await SchemaProbe.run()
                        if !all { exit(0) }
                    }
                    if all || args.contains("--position-probe") {
                        await SchemaProbe.positionProbe()
                        if !all { exit(0) }
                    }
                    if all || args.contains("--retry-probe") {
                        await SchemaProbe.retryProbe()
                        if !all { exit(0) }
                    }
                    if all || args.contains("--branch-battery") {
                        BranchBattery.stopIsDeterministic()
                        await BranchBattery.run()
                        if !all { exit(0) }
                    }
                    if all {
                        print("[RUN-ALL] every harness complete")
                        fflush(stdout)
                        exit(0)
                    }
                }
        }
    }
}

private struct KenyangStoreKey: @preconcurrency EnvironmentKey {
    @MainActor static let defaultValue = KenyangStore(container: KenyangStore.makeContainer(inMemory: true))
}

extension EnvironmentValues {
    var kenyangStore: KenyangStore {
        get { self[KenyangStoreKey.self] }
        set { self[KenyangStoreKey.self] = newValue }
    }
}

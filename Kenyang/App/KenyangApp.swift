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
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.kenyangStore, store)
                .modelContainer(store.container)
                .task {
                    // TESTS.md T50/T51/T52 harness — see Verification/TokenAudit.swift
                    let args = CommandLine.arguments
                    let all = args.contains("--run-all")

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

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

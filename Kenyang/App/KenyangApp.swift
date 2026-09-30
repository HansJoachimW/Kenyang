import AppIntents
import SwiftData
import SwiftUI

@main
struct KenyangApp: App {
    private let store: KenyangStore
    private let session: MealSession
    private let coordinator: RoundCoordinator

    init() {
        let store = KenyangStore(container: KenyangStore.makeContainer())
        let session = MealSession(store: store, display: LiveActivityController.shared)
        let coordinator = RoundCoordinator(session: session)
        self.store = store
        self.session = session
        self.coordinator = coordinator

        AppDependencyManager.shared.add(dependency: store)
        AppDependencyManager.shared.add(dependency: session)
        AppDependencyManager.shared.add(dependency: coordinator)

        // Both must be registered before launch finishes: a Live Activity button can
        // launch the app in the background, and BGTaskScheduler rejects late registration.
        let handler = MealCommandHandler(session: session, coordinator: coordinator)
        ActivityBridge.shared.register { await handler.handle($0) }
        ProactiveTrigger.registerBackgroundTask()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(coordinator)
                .modelContainer(store.container)
                .task { await SpotlightIndexer.reindex(store) }
        }
    }
}

import SwiftUI

struct RootView: View {
    @Environment(MealSession.self) private var session
    @Environment(RoundCoordinator.self) private var coordinator
    @AppStorage(DinerPreferences.onboardedKey) private var isOnboarded = false
    @State private var model: MealViewModel?

    var body: some View {
        if !isOnboarded {
            OnboardingView { isOnboarded = true }
        } else if let model {
            MealFlowView(model: model)
        } else {
            LaunchRingView()
                .task { model = MealViewModel(session: session, coordinator: coordinator) }
        }
    }
}

/// Matches the system launch screen, so launch flows straight into the app.
struct LaunchRingView: View {
    var body: some View {
        Image("LaunchRing")
            .accessibilityHidden(true)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.surface)
    }
}

struct MealFlowView: View {
    @Bindable var model: MealViewModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            screen
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.surface)
                .toolbar {
                    if model.screen != .home {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("How it decided", systemImage: "list.bullet.rectangle") { model.isShowingTrace = true }
                        }
                    }
                }
                .sheet(isPresented: $model.isShowingTrace) {
                    TraceView(trace: model.session.trace)
                }
        }
        .tint(Palette.accent)
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active else { return }
            model.syncWithSession()
            if model.session.visit == nil { LiveActivityController.shared.endAllActivities() }
        }
    }

    @ViewBuilder
    private var screen: some View {
        switch model.screen {
        case .home:                  HomeView(model: model)
        case .planning:              PlanningView(model: model)
        case .plan:                  RoundPlanView(model: model)
        case .eating:                EatingView(model: model)
        case .stop(let reason):      StopView(model: model, reason: reason)
        case .declined(let message): DeclineView(model: model, message: message)
        }
    }
}

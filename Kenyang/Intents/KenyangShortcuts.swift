import AppIntents

/// Phrases share one global namespace, so logging and rating use different words.
struct KenyangShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: RateDishIntent(),
                    phrases: ["Rate a dish in \(.applicationName)",
                              "Rate what I ate in \(.applicationName)"],
                    shortTitle: "Rate a dish",
                    systemImageName: "star")
        AppShortcut(intent: PlanRoundIntent(),
                    phrases: ["What should I eat next in \(.applicationName)",
                              "Plan a round in \(.applicationName)"],
                    shortTitle: "Plan a round",
                    systemImageName: "fork.knife")
        AppShortcut(intent: RecommendStopIntent(),
                    phrases: ["Should I stop in \(.applicationName)",
                              "Am I done in \(.applicationName)"],
                    shortTitle: "Should I stop",
                    systemImageName: "hand.raised")
        AppShortcut(intent: LogEatenIntent(),
                    phrases: ["Log a dish in \(.applicationName)",
                              "I ate something in \(.applicationName)",
                              "Log what I ate in \(.applicationName)"],
                    shortTitle: "Log a dish",
                    systemImageName: "fork.knife.circle")
        AppShortcut(intent: SetFullnessIntent(),
                    phrases: ["Set my fullness in \(.applicationName)",
                              "Say how full I am in \(.applicationName)"],
                    shortTitle: "How full I am",
                    systemImageName: "gauge.medium")
        AppShortcut(intent: EndMealIntent(),
                    phrases: ["End the meal in \(.applicationName)",
                              "I am done in \(.applicationName)"],
                    shortTitle: "End the meal",
                    systemImageName: "flag.checkered")
        AppShortcut(intent: LogNextItemIntent(),
                    phrases: ["Log the next item in \(.applicationName)",
                              "Next plate in \(.applicationName)"],
                    shortTitle: "Log next item",
                    systemImageName: "circle.badge.checkmark")
        AppShortcut(intent: StartSessionIntent(),
                    phrases: ["Start a buffet in \(.applicationName)",
                              "Start a session in \(.applicationName)"],
                    shortTitle: "Start a session",
                    systemImageName: "play")
    }
}

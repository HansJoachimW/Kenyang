import SwiftUI

/// Each stage by name with its own question, and each tool as it returns, because the
/// first stage can take ten times as long as the second.
struct PlanningView: View {
    let model: MealViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var progress: AgentProgress { model.coordinator.progress }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(progress.completed) { done in
                HStack(spacing: 8) {
                    SectionLabel(done.stage.label, tint: Palette.muted)
                    Text("✓ \(done.seconds.formatted(.number.precision(.fractionLength(1)))) s")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Palette.muted)
                }
            }

            if let stage = progress.current {
                currentStage(stage)
            }

            Spacer()

            Button("Skip the AI and plan now") { model.skipTheAI() }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.24), value: progress.completed.count)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.24), value: progress.checks)
    }

    private func currentStage(_ stage: AgentProgress.Stage) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle().fill(Palette.accent).frame(width: 8, height: 8)
                SectionLabel(stage.label)
            }
            Text(stage.question)
                .font(.title3.weight(.medium))
                .foregroundStyle(Palette.ink)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(progress.checks, id: \.self) { check in
                    Text(check.summary)
                        .font(.caption)
                        .foregroundStyle(check.isRefusal ? Palette.unknown : Palette.muted)
                        .transition(.opacity)
                }
            }

            Divider().padding(.top, 4)
            HStack {
                Text("\(progress.stageNumber) of \(progress.stageCount)")
                Spacer()
                Text(stage.typicalDuration)
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(Palette.muted)
        }
    }
}

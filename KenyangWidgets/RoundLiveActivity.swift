import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// The Lock Screen bar and the three Dynamic Island presentations. Each keeps what it
/// has room for: expanded carries the actions, compact the ring and clock, minimal the
/// ring alone. Never a running total, money, or a bar filling toward a ceiling.
struct RoundLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RoundActivityAttributes.self) { context in
            LockScreenBar(venueName: context.attributes.venueName, state: context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        CapacityRing(fraction: context.state.fractionRemaining).frame(width: 26, height: 26)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(context.state.platesText).font(.caption.weight(.medium))
                            Text("Round \(context.state.round)").font(.caption2).foregroundStyle(Palette.muted)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let minutes = context.state.minutesText {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(minutes).font(.caption.weight(.medium))
                            Text("last order").font(.caption2).foregroundStyle(Palette.muted)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    MealActions(state: context.state)
                }
            } compactLeading: {
                CapacityRing(fraction: context.state.fractionRemaining, lineWidth: 4).frame(width: 18, height: 18)
            } compactTrailing: {
                if let minutes = context.state.minutesText {
                    Text(minutes).font(.caption2.weight(.medium)).foregroundStyle(Palette.accent)
                }
            } minimal: {
                CapacityRing(fraction: context.state.fractionRemaining, lineWidth: 4).frame(width: 18, height: 18)
            }
            .keylineTint(Palette.accent)
        }
    }
}

/// What the diner can do right now, so a meal can go on without opening the app.
private struct MealActions: View {
    let state: RoundActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let message = state.message {
                Text(message).font(.caption).lineLimit(2)
            }
            switch state.phase {
            case .planning:
                Text("Planning round \(state.round)…").font(.subheadline)
            case .suggested:
                suggestion
            case .eating:
                if let dish = state.nextDish {
                    Text(dish).font(.subheadline.weight(.medium)).lineLimit(1)
                    buttons(.good, .skip)
                }
            case .roundDone:
                Text("Round \(state.round) done").font(.subheadline.weight(.medium))
                buttons(.nextRound, .endMeal)
            case .timeToStop:
                buttons(.endMeal)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var suggestion: some View {
        Text(state.suggestion.joined(separator: " · ")).font(.subheadline.weight(.medium)).lineLimit(2)
        if let question = state.question {
            Text("Ask staff: does \(question.dish) contain \(question.ingredient)?").font(.caption)
            HStack(spacing: 8) {
                Button(intent: IngredientAnswerIntent(dish: question.dish, ingredient: question.ingredient, contains: false)) { Text("No") }
                Button(intent: IngredientAnswerIntent(dish: question.dish, ingredient: question.ingredient, contains: true)) { Text("Yes") }
            }
            .buttonStyle(.bordered)
            .font(.caption)
        } else {
            buttons(.orderRound, .anotherRound)
        }
    }

    private func buttons(_ actions: MealAction...) -> some View {
        HStack(spacing: 8) {
            ForEach(actions, id: \.self) { action in
                Button(action.label, intent: MealButtonIntent(action))
            }
        }
        .buttonStyle(.bordered)
        .font(.caption)
    }
}

private struct LockScreenBar: View {
    let venueName: String
    let state: RoundActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            CapacityRing(fraction: state.fractionRemaining).frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(venueName).font(.footnote.weight(.medium)).lineLimit(1)
                    Text(state.phase.label).font(.caption2).foregroundStyle(Palette.muted)
                    Spacer(minLength: 0)
                    if let minutes = state.minutesText {
                        Text(minutes).font(.caption2.weight(.medium)).foregroundStyle(Palette.accent)
                    }
                    if state.phase != .roundDone && state.phase != .timeToStop {
                        Button(MealAction.endMeal.label, intent: MealButtonIntent(.endMeal))
                            .buttonStyle(.bordered)
                            .font(.caption2)
                    }
                }
                Text("\(state.platesText) left · round \(state.round)").font(.caption).foregroundStyle(Palette.muted)
                MealActions(state: state)
            }
        }
        .padding(16)
        .foregroundStyle(Palette.ink)
        .activityBackgroundTint(Palette.surface)
        .activitySystemActionForegroundColor(Palette.ink)
    }
}

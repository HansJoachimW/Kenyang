import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// The lock-screen bar and all three Dynamic Island presentations.
///
/// **They rank rather than shrink.** Expanded carries the target and both actions;
/// compact drops the target; minimal drops everything but the capacity ring. Each
/// presentation decides what it can afford to lose, instead of rendering the same
/// layout at three sizes.
///
/// **Never here:** a running total of anything eaten, money, or a progress bar toward a
/// ceiling that does not exist. The ring shows capacity *remaining*, which counts down.
struct RoundLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RoundActivityAttributes.self) { context in
            LockScreenBar(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Palette.surface)
                .activitySystemActionForegroundColor(Palette.ink)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        CapacityRing(fraction: context.state.fractionRemaining)
                            .frame(width: 26, height: 26)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(context.state.platesText)
                                .font(.caption.weight(.medium))
                            Text("Round \(context.state.roundIndex)")
                                .font(.caption2).foregroundStyle(Palette.muted)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let minutes = context.state.minutesText {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(minutes).font(.caption.weight(.medium))
                            Text("last order").font(.caption2).foregroundStyle(Palette.muted)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedBottom(state: context.state)
                }
            } compactLeading: {
                CapacityRing(fraction: context.state.fractionRemaining, lineWidth: 4)
                    .frame(width: 18, height: 18)
            } compactTrailing: {
                // Compact drops the target and keeps the clock, because the clock is the
                // half the diner cannot recover by looking at their own plate.
                if let minutes = context.state.minutesText {
                    Text(minutes).font(.caption2.weight(.medium)).foregroundStyle(Palette.accent)
                }
            } minimal: {
                CapacityRing(fraction: context.state.fractionRemaining, lineWidth: 4)
                    .frame(width: 18, height: 18)
            }
            .keylineTint(Palette.accent)
        }
    }
}

/// The two working buttons, and what they are rating.
///
/// The design says *"Rate and Stop as real buttons"*. A single **Rate** would have to
/// mean *good*, and an app whose whole stance is "stop before you regret it" cannot
/// ship a one-tap control that can only say the food was excellent. So the two buttons
/// are **Good** and **Skip** — a real rating with a real negative — and Stop lives on
/// the lock-screen bar, which has the room for it.
///
/// Unlike the Action Button, this rates: the dish is named right above the buttons, so
/// the diner can see what they are answering about. That is the whole difference.
private struct ExpandedBottom: View {
    let state: RoundActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let message = state.message {
                Text(message).font(.caption).foregroundStyle(Palette.ink)
            }
            if let target = state.nextTarget {
                Text(target).font(.subheadline.weight(.medium)).lineLimit(1)
                HStack(spacing: 8) {
                    Button(intent: RateTargetGoodIntent()) {
                        Label("Good", systemImage: "hand.thumbsup")
                    }
                    Button(intent: RateTargetSkipIntent()) {
                        Label("Skip", systemImage: "hand.thumbsdown")
                    }
                }
                .buttonStyle(.bordered)
                .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The lock-screen bar, in the same four states as the Island.
private struct LockScreenBar: View {
    let attributes: RoundActivityAttributes
    let state: RoundActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            CapacityRing(fraction: state.fractionRemaining)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(attributes.venueName)
                        .font(.footnote.weight(.medium))
                        .lineLimit(1)
                    Text(PhaseLabel.word(for: state.phase))
                        .font(.caption2)
                        .foregroundStyle(Palette.muted)
                }
                Text("\(state.platesText) left · round \(state.roundIndex)")
                    .font(.caption).foregroundStyle(Palette.muted)

                if let message = state.message {
                    Text(message).font(.caption).foregroundStyle(Palette.ink).lineLimit(2)
                } else if let target = state.nextTarget {
                    Text("Next: \(target)").font(.caption).foregroundStyle(Palette.ink).lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            VStack(spacing: 6) {
                if let minutes = state.minutesText {
                    Text(minutes).font(.caption2.weight(.medium)).foregroundStyle(Palette.accent)
                }
                Button(intent: StopFromActivityIntent()) { Text("Stop") }
                    .buttonStyle(.bordered)
                    .font(.caption2)
            }
        }
        .padding(14)
    }
}

/// Colour is never the only indicator — every state carries a word.
private enum PhaseLabel {
    static func word(for phase: RoundActivityAttributes.Phase) -> String {
        switch phase {
        case .planning:  "planning"
        case .active:    "eating"
        case .stopGuard: "time to stop"
        case .degraded:  "no model"
        }
    }
}

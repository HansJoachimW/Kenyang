import AppIntents
import SwiftUI
import WidgetKit

/// Room left in the meal. The home-screen sizes also start and end a meal without
/// opening the app; they never log food, because every log runs the stop check.
struct CapacityWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KenyangCapacity", provider: SnapshotProvider()) { entry in
            CapacityWidgetView(snapshot: entry.snapshot)
                .containerBackground(Palette.surface, for: .widget)
        }
        .configurationDisplayName("Capacity")
        .description("How much room is left in the current meal.")
        .supportedFamilies([.systemSmall, .systemMedium,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: MealSnapshot
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: MealSnapshotStore.read() ?? .placeholder))
    }

    /// The app reloads the timeline whenever the meal changes.
    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: .now, snapshot: MealSnapshotStore.read() ?? .placeholder)
        completion(Timeline(entries: [entry], policy: .never))
    }
}

struct CapacityWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: MealSnapshot

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(snapshot.isActive ? "\(snapshot.platesText) left" : "No meal")

        case .accessoryCircular:
            CapacityRing(fraction: snapshot.fractionRemaining, lineWidth: 4)

        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 0) {
                Text(snapshot.venueName).font(.headline).lineLimit(1)
                Text(snapshot.isActive ? "\(snapshot.platesText) left" : "No meal in progress")
                    .font(.caption)
                if let target = snapshot.nextDish {
                    Text("Next: \(target)").font(.caption2).lineLimit(1)
                }
            }

        case .systemMedium:
            HStack(spacing: 16) {
                ring(size: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(snapshot.venueName).font(.headline).lineLimit(1)
                    Text(detail).font(.subheadline).foregroundStyle(Palette.muted)
                    if let target = snapshot.nextDish {
                        Text("Next: \(target)").font(.caption).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    mealButton
                }
                Spacer(minLength: 0)
            }

        default:
            VStack(spacing: 8) {
                ring(size: 48)
                Text(detail).font(.caption).foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                mealButton
            }
        }
    }

    /// Ending from here can't say why the meal ended, so it is recorded as unknown.
    private var mealButton: some View {
        let action: MealAction = snapshot.isActive ? .endMeal : .startMeal
        return Button(action.label, intent: MealButtonIntent(action))
            .buttonStyle(.bordered)
            .tint(Palette.accent)
            .font(.caption.weight(.medium))
    }

    private func ring(size: CGFloat) -> some View {
        CapacityRing(fraction: snapshot.fractionRemaining)
            .frame(width: size, height: size)
            .opacity(snapshot.isActive ? 1 : 0.4)
    }

    private var detail: String {
        snapshot.isActive ? "\(snapshot.platesText) left · round \(snapshot.round)"
                          : "No meal in progress"
    }
}

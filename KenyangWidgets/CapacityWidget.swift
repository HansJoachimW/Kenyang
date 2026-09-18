import SwiftUI
import WidgetKit

/// The home-screen and lock-screen widget family, off the same capacity ring.
///
/// Read-only by design: every control in this app runs the stop check, and a widget
/// tap that logs food without one would route around the guardrail that exists because
/// the model would not choose to stop. Tapping opens the app.
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

    /// One entry, never a schedule. Capacity only changes when the diner logs something,
    /// and the app reloads the timeline when it does — a widget that refreshed on a
    /// clock would be inventing movement the meal has not made.
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
            VStack(alignment: .leading, spacing: 1) {
                Text(snapshot.venueName).font(.headline).lineLimit(1)
                Text(snapshot.isActive ? "\(snapshot.platesText) left" : "No meal in progress")
                    .font(.caption)
                if let target = snapshot.nextTarget {
                    Text("Next: \(target)").font(.caption2).lineLimit(1)
                }
            }

        case .systemMedium:
            HStack(spacing: 16) {
                ring(size: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(snapshot.venueName).font(.headline).lineLimit(1)
                    Text(detail).font(.subheadline).foregroundStyle(Palette.muted)
                    if let target = snapshot.nextTarget {
                        Text("Next: \(target)").font(.caption).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }

        default:
            VStack(spacing: 8) {
                ring(size: 60)
                Text(detail).font(.caption).foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func ring(size: CGFloat) -> some View {
        CapacityRing(fraction: snapshot.fractionRemaining)
            .frame(width: size, height: size)
            .opacity(snapshot.isActive ? 1 : 0.4)
    }

    private var detail: String {
        snapshot.isActive ? "\(snapshot.platesText) left · round \(snapshot.roundIndex)"
                          : "No meal in progress"
    }
}

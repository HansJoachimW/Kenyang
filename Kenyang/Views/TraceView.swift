import SwiftUI

/// How each round was decided, marking what Kenyang calculated and what the AI wrote.
struct TraceView: View {
    let trace: TraceLog
    @State private var expanded: TraceEntry.ID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            List(trace.entries) { entry in
                if let override = entry.override {
                    OverrideRow(entry: entry, override: override, isExpanded: expandedBinding(for: entry))
                } else {
                    EntryRow(entry: entry)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Palette.surface)
            .navigationTitle("How it decided")
            .navigationBarTitleDisplayMode(.inline)
            .overlay {
                if trace.entries.isEmpty {
                    ContentUnavailableView("Nothing decided yet", systemImage: "list.bullet.rectangle",
                                           description: Text("Each round's reasoning shows up here."))
                }
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: expanded)
    }

    private func expandedBinding(for entry: TraceEntry) -> Binding<Bool> {
        Binding(get: { expanded == entry.id }, set: { expanded = $0 ? entry.id : nil })
    }
}

private struct EntryRow: View {
    let entry: TraceEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.heading).font(.subheadline.weight(.medium)).foregroundStyle(Palette.ink)
                Spacer()
                AttributionBadge(isCalculated: entry.isCalculated)
            }
            if entry.isWorthShowingInFull {
                Text(entry.detail).font(.caption).foregroundStyle(Palette.ink)
            } else {
                DisclosureGroup {
                    Text("\(entry.title): \(entry.detail)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(Palette.muted)
                        .textSelection(.enabled)
                } label: {
                    Text("Technical details").font(.caption).foregroundStyle(Palette.muted)
                }
            }
        }
        .padding(.vertical, 8)
        .listRowBackground(Palette.surface)
    }
}

/// A guard overruling the AI: what it said, what it chose (struck through), and what
/// Kenyang did instead.
private struct OverrideRow: View {
    let entry: TraceEntry
    let override: GuardOverride
    @Binding var isExpanded: Bool

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                part("What the AI said") {
                    Text("\u{201C}\(override.wrote)\u{201D}")
                        .font(.footnote)
                        .foregroundStyle(Palette.ink)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.muted.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                }
                part("What the AI then chose") {
                    Text(override.chose.label)
                        .font(.title3.weight(.semibold))
                        .strikethrough()
                        .foregroundStyle(Palette.muted)
                }
                part("What Kenyang did") {
                    Text(override.did).font(.footnote).foregroundStyle(Palette.ink)
                    Text(override.forced.label).font(.title3.weight(.semibold)).foregroundStyle(Palette.accent)
                }
                Text("Kenyang overruling the AI is the app working as designed. It does this on a fixed rule, never on a hunch.")
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
            }
            .padding(.top, 8)
        } label: {
            Text(entry.heading).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.accent)
        }
        .padding(12)
        .background(Palette.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .listRowBackground(Palette.surface)
    }

    private func part<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(label, tint: Palette.muted)
            content()
        }
    }
}

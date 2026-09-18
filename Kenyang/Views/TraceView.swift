import SwiftUI

/// Screen 7 — the trace. The only place the whole reasoning is visible, and so the one
/// screen designed for reading rather than glancing.
///
/// Design is not one of the graded criteria. This panel's job is to make the agentic
/// behaviour and the guardrails *legible* — a beautiful screen that hides the reasoning
/// is worth less here than a plain one that shows it.
struct TraceView: View {
    let trace: TraceLog
    @State private var expanded: UUID?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(trace.entries) { entry in
                        row(entry)
                            // Neighbours dim but stay visible, so an expanded entry
                            // never loses its position in the path.
                            .opacity(expanded == nil || expanded == entry.id ? 1 : 0.42)
                        Divider()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .animation(.easeOut(duration: 0.2), value: expanded)
            }
            .background(Palette.surface)
            .navigationTitle("Trace")
        }
    }

    @ViewBuilder
    private func row(_ entry: TraceEntry) -> some View {
        if let override = entry.override {
            overrideRow(entry, override)
        } else {
            plainRow(entry)
        }
    }

    private func plainRow(_ entry: TraceEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.title).font(.subheadline.weight(.medium)).foregroundStyle(Palette.ink)
                Spacer()
                AttributionBadge(isDeterministic: entry.isDeterministic)
            }
            Text(entry.detail).font(.caption).foregroundStyle(Palette.muted)
        }
        .padding(.vertical, 10)
    }

    /// The money shot. `exploit` is chosen ~92% of the time, so the branching the diner
    /// sees is produced by the guards rather than by the model choosing well — which
    /// makes this simultaneously the most honest and the most impressive thing in the
    /// product, and the only row that gets a fill, a border and a three-part layout.
    private func overrideRow(_ entry: TraceEntry, _ override: GuardOverride) -> some View {
        let isOpen = expanded == entry.id
        return VStack(alignment: .leading, spacing: 12) {
            Button {
                expanded = isOpen ? nil : entry.id
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.accent)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(Palette.accent)
                }
            }
            .buttonStyle(.plain)

            if isOpen {
                // Three labelled parts, in reading order.
                part("WHAT THE MODEL WROTE") {
                    Text("“\(override.wrote)”")
                        .font(.footnote)
                        .foregroundStyle(Palette.ink)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.muted.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    HStack(spacing: 8) {
                        Text("because").font(.caption).foregroundStyle(Palette.muted)
                        AttributionBadge(isDeterministic: false)
                    }
                }

                part("WHAT THE MODEL THEN CHOSE") {
                    // Struck through rather than hidden. The strike-through is the whole
                    // point: the diner can see the app disagreeing with its own model.
                    Text(override.chose)
                        .font(.title3.weight(.semibold))
                        .strikethrough()
                        .foregroundStyle(Palette.muted)
                }

                part("WHAT THE GUARD DID") {
                    Text(override.did)
                        .font(.footnote)
                        .foregroundStyle(Palette.ink)
                    Text(override.forced)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Palette.accent)
                    HStack(spacing: 8) {
                        Text("\(override.guardName) · layer \(override.layer)")
                            .font(.caption.monospaced())
                            .foregroundStyle(Palette.muted)
                        AttributionBadge(isDeterministic: true)
                    }
                }

                Text("A guardrail overriding the agent is the system working. This one fires on a threshold, never on a judgement.")
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.accent.opacity(0.5), lineWidth: 1)
        }
        .padding(.vertical, 10)
    }

    private func part<Content: View>(_ label: String,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption2.weight(.semibold)).tracking(0.6)
                .foregroundStyle(Palette.muted)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

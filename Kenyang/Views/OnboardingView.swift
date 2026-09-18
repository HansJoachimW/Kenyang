import SwiftUI

/// Screen 1 — the stance, then the list. Roughly sixty seconds, once, ever.
///
/// Not a feature tour. One sentence saying which side the app is on, and one promising
/// it will recommend stopping. Everything the app later refuses to do is legible from
/// here.
///
/// It also builds the avoid list, which had no front door anywhere in the app until
/// now: `KenyangStore.addExclusion` existed, the ternary `ExclusionValidator` was built
/// on it and eight guardrail references read it, and no screen ever called it.
struct OnboardingView: View {
    @Environment(\.kenyangStore) private var store

    @AppStorage("onboarding.completed") private var completed = false
    @AppStorage("onboarding.plates") private var plates: Double = SessionDefaults.plates

    @State private var exclusions: [String] = []
    @State private var draft = ""
    @State private var addingIngredient = false

    let onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                stance
                avoidList
                capacity
            }
            .padding(24)
        }
        .background(Palette.surface)
        .safeAreaInset(edge: .bottom) {
            Button(action: finish) {
                Text("Done").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.accent)
            .controlSize(.large)
            .padding(24)
            .background(Palette.surface)
        }
        .task { exclusions = store.exclusions() }
    }

    // MARK: -

    private var stance: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("The goal is kenyang, not maximum.")
                .font(.largeTitle.bold())
                .foregroundStyle(Palette.ink)
            Text("Kenyang plans a meal as a sequence under a shrinking budget. It proposes; you decide. It will tell you to stop.")
                .font(.subheadline)
                .foregroundStyle(Palette.ink)
        }
    }

    private var avoidList: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Anything you need to avoid?")

            // The chips are the only place Dark Wine appears: this is the list the diner
            // authored, and the one thing in the app nothing else overrides. The ✕
            // carries the meaning when the colour is not seen.
            FlowRow(spacing: 8) {
                ForEach(exclusions, id: \.self) { term in
                    Button {
                        store.removeExclusion(term)
                        exclusions = store.exclusions()
                    } label: {
                        HStack(spacing: 6) {
                            Text(term).font(.subheadline.weight(.medium))
                            Image(systemName: "xmark").font(.caption2.weight(.bold))
                        }
                        .foregroundStyle(Palette.surface)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Palette.excluded, in: Capsule())
                    }
                    .accessibilityLabel("Remove \(term) from the avoid list")
                }

                Button { addingIngredient = true } label: {
                    Text("add an ingredient")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Palette.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().strokeBorder(Palette.muted, lineWidth: 1))
                }
            }

            // No "why" field, no allergy/preference toggle, no severity. Allergy,
            // dietary law, diagnosis and dislike all enter the same way and are enforced
            // identically. Not collecting is a stronger guarantee than protecting what
            // was collected.
            Text("Ingredients only. Kenyang never asks why something is on this list, and nothing in the app reads a reason.")
                .font(.caption)
                .foregroundStyle(Palette.muted)
        }
        .alert("Add an ingredient", isPresented: $addingIngredient) {
            TextField("e.g. shellfish", text: $draft)
                .textInputAutocapitalization(.never)
            Button("Cancel", role: .cancel) { draft = "" }
            Button("Add") {
                store.addExclusion(draft)
                exclusions = store.exclusions()
                draft = ""
            }
        }
    }

    private var capacity: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("How much is a full meal for you?")

            // Five options, no slider, no units. It is a prior, not a measurement — the
            // within-meal and across-meal layers correct it. Asking for precision the
            // app cannot use would be theatre.
            HStack(spacing: 10) {
                ForEach([2.0, 3.0, 4.0, 5.0, 6.0], id: \.self) { value in
                    Button { plates = value } label: {
                        Text("\(Int(value))")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .foregroundStyle(plates == value ? Palette.surface : Palette.ink)
                            .background {
                                if plates == value {
                                    RoundedRectangle(cornerRadius: 10).fill(Palette.accent)
                                } else {
                                    RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.muted, lineWidth: 1)
                                }
                            }
                    }
                    .accessibilityLabel("\(Int(value)) plates")
                    .accessibilityAddTraits(plates == value ? [.isSelected] : [])
                }
            }

            Text("plates, roughly. It corrects itself as you eat.")
                .font(.caption)
                .foregroundStyle(Palette.muted)
        }
    }

    private func finish() {
        completed = true
        onDone()
    }
}

/// The small caps label the design uses above every group.
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(0.6)
            .foregroundStyle(Palette.accent)
    }
}

/// Chips wrap; `HStack` does not. Small enough to keep local rather than reach for a
/// layout dependency.
struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? x, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

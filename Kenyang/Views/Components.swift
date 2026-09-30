import SwiftUI

/// The caps label above every group.
struct SectionLabel: View {
    let text: String
    var tint = Palette.accent

    init(_ text: String, tint: Color = Palette.accent) {
        self.text = text
        self.tint = tint
    }

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(0.6)
            .foregroundStyle(tint)
    }
}

struct AvoidChip: View {
    let term: String
    var isRemovable = false

    var body: some View {
        HStack(spacing: 8) {
            Text(term).font(.subheadline.weight(.medium))
            if isRemovable {
                Image(systemName: "xmark").font(.caption2.weight(.bold))
            }
        }
        .foregroundStyle(Palette.surface)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Palette.excluded, in: Capsule())
    }
}

/// New dishes are outlined, tried ones filled; the word carries the meaning without colour.
struct RoundRoleBadge: View {
    let isNew: Bool

    var body: some View {
        OutlinedOrFilledBadge(text: isNew ? "new" : "tried", isFilled: !isNew)
            .accessibilityLabel(isNew ? "new to you" : "tried before")
    }
}

/// What the app calculated is outlined; what the AI wrote is filled.
struct AttributionBadge: View {
    let isCalculated: Bool

    var body: some View {
        OutlinedOrFilledBadge(text: isCalculated ? "calculated" : "AI", isFilled: !isCalculated)
            .accessibilityLabel(isCalculated ? "calculated by Kenyang" : "written by Apple Intelligence")
    }
}

struct VerdictBadge: View {
    let verdict: ExclusionVerdict

    var body: some View {
        Text(verdict.label)
            .font(.caption2.weight(.medium))
            .foregroundStyle(verdict.tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(verdict.tint.opacity(0.12), in: Capsule())
    }
}

private struct OutlinedOrFilledBadge: View {
    let text: String
    let isFilled: Bool

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(isFilled ? Palette.surface : Palette.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background {
                if isFilled {
                    Capsule().fill(Palette.accent)
                } else {
                    Capsule().strokeBorder(Palette.accent, lineWidth: 1)
                }
            }
    }
}

extension ExclusionVerdict {
    var label: String {
        switch self {
        case .safe:     "safe"
        case .excluded: "excluded"
        case .unknown:  "ask staff"
        }
    }

    var tint: Color {
        switch self {
        case .safe:     Palette.safe
        case .excluded: Palette.excluded
        case .unknown:  Palette.unknown
        }
    }
}

/// Wraps chips onto the next line.
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

import SwiftUI

// The colour tokens moved to Shared/DesignTokens.swift so the widget extension can
// render the same capacity ring. What stays here extends app-only domain types.

extension ExclusionVerdict {
    var tint: Color {
        switch self {
        case .safe:     Palette.safe
        case .excluded: Palette.excluded
        case .unknown:  Palette.unknown
        }
    }

    var word: String {
        switch self {
        case .safe:     "safe"
        case .excluded: "excluded"
        case .unknown:  "ask staff"
        }
    }
}

extension TraceKind {
    var tint: Color {
        switch self {
        case .modelFailure: Palette.muted
        default:            Palette.accent
        }
    }
}

/// Recon outline, exploit fill — the design's third binding rule. Both are Blue Slate,
/// because the fourth rule says Blue Slate is the only fill and amber only ever means
/// uncertainty; recon is not uncertainty, it is a deliberate spend. The word carries the
/// meaning when the colour is not seen.
struct RoundRoleBadge: View {
    let isRecon: Bool

    var body: some View {
        Text(isRecon ? "recon" : "exploit")
            .font(.caption2.weight(.medium))
            .foregroundStyle(isRecon ? Palette.accent : Palette.surface)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background {
                if isRecon {
                    Capsule().strokeBorder(Palette.accent, lineWidth: 1)
                } else {
                    Capsule().fill(Palette.accent)
                }
            }
            .accessibilityLabel(isRecon ? "reconnaissance" : "exploit")
    }
}

/// The same rule one level up: what the app COMPUTED is outlined, what the MODEL
/// produced is filled. The trace panel is the one screen designed for reading, and this
/// is the distinction it exists to make legible.
struct AttributionBadge: View {
    let isDeterministic: Bool

    var body: some View {
        Text(isDeterministic ? "COMPUTED" : "MODEL")
            .font(.caption2.weight(.medium))
            .foregroundStyle(isDeterministic ? Palette.accent : Palette.surface)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background {
                if isDeterministic {
                    Capsule().strokeBorder(Palette.accent, lineWidth: 1)
                } else {
                    Capsule().fill(Palette.accent)
                }
            }
    }
}

struct VerdictBadge: View {
    let verdict: ExclusionVerdict

    var body: some View {
        Text(verdict.word)
            .font(.caption2.weight(.medium))
            .foregroundStyle(verdict.tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(verdict.tint.opacity(0.12), in: Capsule())
            .accessibilityLabel(verdict.word)
    }
}

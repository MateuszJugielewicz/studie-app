import SwiftUI

/// Cosmetic "EasySesh team" badge. It shows who works at EasySesh; it grants no rights in the app.
struct AdminBadge: View {
    var compact = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "sparkle")
                .font(.system(size: compact ? 8 : 9, weight: .black))
            if !compact {
                Text("TEAM")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.8)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, compact ? 5 : 7)
        .padding(.vertical, 3)
        .background(Theme.neon, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.6))
        .neonGlow(Theme.magenta, radius: 5)
        .accessibilityElement()
        .accessibilityLabel("EasySesh team")
    }
}

/// Special tag only admins can add to a studio, e.g. "Staff pick".
struct SpecialTagChip: View {
    let title: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "star.fill").font(.system(size: 9, weight: .bold))
            Text(localized: title).font(.caption.weight(.bold))
        }
        .foregroundStyle(Theme.neon)
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(Theme.magenta.opacity(0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.neon, lineWidth: 1))
    }
}

/// Marks a studio that paid to be promoted.
struct PromotedTag: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "megaphone.fill").font(.system(size: 9, weight: .bold))
            Text("Promoted").font(.caption2.weight(.heavy)).textCase(.uppercase).tracking(0.6)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(Theme.neon, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.6))
        .neonGlow(Theme.magenta, radius: 6)
        .accessibilityLabel("Promoted studio")
    }
}

/// Stars + average, e.g. for an artist's rating from studios.
struct RatingPill: View {
    let average: Double
    let count: Int

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "star.fill").foregroundStyle(Theme.neon)
            Text(count == 0 ? "–" : String(format: "%.1f", average)).fontWeight(.heavy)
            Text("(\(count))").foregroundStyle(.secondary)
        }
        .font(.subheadline)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Theme.card.opacity(0.78), in: Capsule())
    }
}

import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

// Glance's score pieces (#2463): the Effort target bar and its status line, and the link row the score
// pages use.
// Every figure arrives already resolved by the caller from the same state the hero reads; nothing is
// computed afresh, so these pieces and the rest of Today cannot disagree.

/// A horizontal Effort axis with today's target band shaded, today's Effort filled in, and the band's
/// edges numbered under the track so the target reads as figures, not only as a shape.
struct EffortTargetBar: View {
    let axisMax: Double
    let band: ClosedRange<Double>?
    let effort: Double?
    /// Decimal places for the band-edge numbers under the track (1 on the 0–21 scale, 0 on 0–100), or
    /// nil for none — where the range is already printed beside the bar, a second copy is noise.
    var decimals: Int? = nil

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(StrandPalette.surfaceInset)
                    if let band {
                        Capsule()
                            .fill(StrandPalette.effortColor.opacity(0.35))
                            .frame(width: max(0, x(band.upperBound, geo.size.width) - x(band.lowerBound, geo.size.width)))
                            .offset(x: x(band.lowerBound, geo.size.width))
                    }
                    if let effort {
                        Capsule()
                            .fill(StrandPalette.effortColor)
                            .frame(width: x(effort, geo.size.width))
                    }
                }
            }
            .frame(height: 10)
            if let band, decimals != nil {
                GeometryReader { geo in
                    ZStack(alignment: .topLeading) {
                        edge(band.lowerBound, geo.size.width)
                        edge(band.upperBound, geo.size.width)
                    }
                }
                .frame(height: 16)
            }
        }
        .accessibilityHidden(true)
    }

    /// A band edge's number, centred under its point on the track and kept inside the card.
    private func edge(_ v: Double, _ width: CGFloat) -> some View {
        let f = "%.\(decimals ?? 0)f"
        return Text(verbatim: String(format: f, locale: AppLanguage.activeLocale, v))
            .font(StrandFont.captionNumber)
            .foregroundStyle(StrandPalette.textSecondary)
            .fixedSize()
            .position(x: min(max(x(v, width), 12), width - 12), y: 8)
    }

    /// `v` on the axis, as a horizontal position within `width`, clamped to the track.
    private func x(_ v: Double, _ width: CGFloat) -> CGFloat {
        CGFloat(max(0, min(v, axisMax)) / axisMax) * width
    }
}

/// One-line read of where today's Effort stands against its target, shared by the card and the sheet so
/// the two always say the same thing.
struct EffortTargetStatusText: View {
    let standing: EffortTarget.Standing?
    let hasBand: Bool
    let decimals: Int

    var body: some View {
        Text(verbatim: message)
            .font(StrandFont.caption)
            .foregroundStyle(StrandPalette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var message: String {
        guard hasBand else { return String(localized: "No target until today's Charge is scored.") }
        switch standing {
        case .below(let toGo):
            let n = String(format: "%.\(decimals)f", locale: AppLanguage.activeLocale, toGo)
            return String(localized: "\(n) to go to reach today's target")
        case .within: return String(localized: "In today's target range")
        case .above:  return String(localized: "Above today's target range")
        case nil:     return String(localized: "No Effort yet today.")
        }
    }
}

// MARK: - Shared pieces

/// A tappable row under a score's breakdown.
struct GlanceLinkRow: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: NoopMetrics.space3) {
            Image(systemName: icon)
                .foregroundStyle(StrandPalette.accent)
                .accessibilityHidden(true)
            Text(verbatim: title)
                .font(StrandFont.body)
                .foregroundStyle(StrandPalette.textPrimary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textTertiary)
                .accessibilityHidden(true)
        }
        .padding(NoopMetrics.cardPadding)
        .background(NoopPanelSurface(cornerRadius: 18))
        .contentShape(Rectangle())
    }
}

/// Minutes as a localised "7h 32m", using the system's unit words so no new strings are introduced.
enum GlanceDuration {
    static func text(minutes: Double) -> String {
        let f = DateComponentsFormatter()
        f.allowedUnits = minutes >= 60 ? [.hour, .minute] : [.minute]
        f.unitsStyle = .abbreviated
        f.zeroFormattingBehavior = .dropLeading
        return f.string(from: max(0, minutes) * 60) ?? "—"
    }
}

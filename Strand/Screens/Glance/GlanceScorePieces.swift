import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

// Glance's score pieces (#2463): the Effort target card and bar, and the link rows the score pages use.
// Every figure arrives already resolved by the caller from the same state the hero reads; nothing is
// computed afresh, so these pieces and the rest of Today cannot disagree.

/// A horizontal Effort axis with today's target band shaded and today's Effort marked.
struct EffortTargetBar: View {
    let axisMax: Double
    let band: ClosedRange<Double>?
    let effort: Double?

    var body: some View {
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
        .accessibilityHidden(true)
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

/// Today's Effort against the range worth aiming for, given today's Charge. Taps through to the Effort
/// sheet.
struct EffortTargetCard: View {
    let effort: Double?
    let band: ClosedRange<Double>?
    let scale: EffortScale
    let onOpen: () -> Void

    private var decimals: Int { scale == .whoop ? 1 : 0 }

    var body: some View {
        Button(action: onOpen) {
            NoopCard(tint: StrandPalette.effortColor) {
                VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Today's Effort target").strandOverline()
                        Spacer()
                        if let band {
                            Text(verbatim: rangeText(band))
                                .font(StrandFont.number(17))
                                .foregroundStyle(StrandPalette.textPrimary)
                        }
                    }
                    EffortTargetBar(axisMax: EffortTarget.axisMax(scale), band: band, effort: effort)
                    EffortTargetStatusText(standing: EffortTarget.standing(effort: effort, band: band),
                                           hasBand: band != nil, decimals: decimals)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Opens the trend and readings"))
    }

    private func rangeText(_ b: ClosedRange<Double>) -> String {
        let f = "%.\(decimals)f"
        return String(format: "\(f)–\(f)", locale: AppLanguage.activeLocale, b.lowerBound, b.upperBound)
    }
}

// MARK: - Shared pieces

/// A tappable row under a score's breakdown.
struct SimpleSheetLinkRow: View {
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

/// A `SimpleSheetLinkRow` pushing a `TabRoute` inside the sheet's own stack.
struct SimpleSheetLink: View {
    let title: String
    let icon: String
    let route: TabRoute

    var body: some View {
        NavigationLink(value: route) { SimpleSheetLinkRow(title: title, icon: icon) }
            .buttonStyle(.plain)
    }
}

/// Minutes as a localised "7h 32m", using the system's unit words so no new strings are introduced.
enum SimpleDuration {
    static func text(minutes: Double) -> String {
        let f = DateComponentsFormatter()
        f.allowedUnits = minutes >= 60 ? [.hour, .minute] : [.minute]
        f.unitsStyle = .abbreviated
        f.zeroFormattingBehavior = .dropLeading
        return f.string(from: max(0, minutes) * 60) ?? "—"
    }
}

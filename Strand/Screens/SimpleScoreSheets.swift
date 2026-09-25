import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

// Simple view's score pieces (#2463): the Effort target card on Today, and the Effort and Rest sheets a
// hero ring opens. Every figure here arrives already resolved by the caller from the same state the hero
// reads, or is read through an existing Repository resolver; nothing is computed afresh, so these views
// and the full Today cannot disagree.

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

// MARK: - Effort sheet

/// What Effort is made of today: the score against its target, and time in each heart-rate zone.
struct SimpleEffortSheet: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    let effort: Double?
    let band: ClosedRange<Double>?
    let scale: EffortScale
    /// The window the hero's Effort covers, so zone time and the score describe the same stretch.
    let from: Int
    let to: Int
    let onClose: () -> Void

    @State private var zoneMinutes: [Double]?

    private var decimals: Int { scale == .whoop ? 1 : 0 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                    NoopCard(padding: 18, tint: StrandPalette.effortColor) {
                        VStack(alignment: .leading, spacing: NoopMetrics.cardInnerSpacing) {
                            SimpleScoreHeader(value: effort.map {
                                String(format: "%.\(decimals)f", locale: AppLanguage.activeLocale, $0)
                            }, name: String(localized: "Effort"))
                            EffortTargetBar(axisMax: EffortTarget.axisMax(scale), band: band, effort: effort)
                            EffortTargetStatusText(standing: EffortTarget.standing(effort: effort, band: band),
                                                   hasBand: band != nil, decimals: decimals)
                        }
                    }
                    zonesCard
                    SimpleSheetLink(title: String(localized: "See your Effort over time"),
                                    icon: "chart.line.uptrend.xyaxis",
                                    route: .metric(HeroRingMetric.effort))
                    NavigationLink {
                        ScoringGuideView(initialSection: .effort, onClose: onClose)
                    } label: {
                        SimpleSheetLinkRow(title: String(localized: "How Effort is scored"), icon: "info.circle")
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, NoopMetrics.screenHPadding)
                .padding(.vertical, NoopMetrics.space4)
            }
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .navigationTitle(Text("Effort"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .tabRouteDestinations()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onClose).foregroundStyle(StrandPalette.accent)
                }
            }
            .task {
                zoneMinutes = await repo.workoutZoneMinutes(from: from, to: to, zoneSet: profile.hrZoneSet)
            }
        }
    }

    @ViewBuilder private var zonesCard: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                Text("HR Zones").strandOverline()
                if let z = zoneMinutes, z.count == 5, z.reduce(0, +) > 0 {
                    let total = z.reduce(0, +)
                    GeometryReader { geo in
                        HStack(spacing: 2) {
                            ForEach(0..<5, id: \.self) { i in
                                Rectangle()
                                    .fill(StrandPalette.hrZoneColor(i + 1))
                                    .frame(width: max(0, CGFloat(z[i] / total) * geo.size.width))
                            }
                        }
                    }
                    .frame(height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .accessibilityHidden(true)
                    HStack(spacing: 0) {
                        ForEach(0..<5, id: \.self) { i in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Z\(i + 1)").strandOverline()
                                Text(verbatim: SimpleDuration.text(minutes: z[i]))
                                    .font(StrandFont.captionNumber)
                                    .foregroundStyle(StrandPalette.textPrimary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } else {
                    Text("No heart-rate zone time recorded today yet.")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
            }
        }
    }
}

// MARK: - Rest sheet

/// What Rest is made of: the night's time asleep, efficiency, stages and disturbances.
struct SimpleRestSheet: View {
    let restScore: Double?
    /// The same day row the hero reads.
    let day: DailyMetric?
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                    NoopCard(padding: 18, tint: StrandPalette.restColor) {
                        VStack(alignment: .leading, spacing: NoopMetrics.cardInnerSpacing) {
                            SimpleScoreHeader(value: restScore.map { "\(Int($0.rounded()))" },
                                              name: String(localized: "Rest"))
                            if let day, day.totalSleepMin != nil {
                                Divider().overlay(StrandPalette.hairline)
                                restRow(String(localized: "Time asleep"), day.totalSleepMin.map { SimpleDuration.text(minutes: $0) })
                                restRow(String(localized: "Efficiency"), day.efficiency.map { "\(Int($0.rounded()))%" })
                                restRow(String(localized: "Deep"), day.deepMin.map { SimpleDuration.text(minutes: $0) })
                                restRow(String(localized: "REM"), day.remMin.map { SimpleDuration.text(minutes: $0) })
                                restRow(String(localized: "Light"), day.lightMin.map { SimpleDuration.text(minutes: $0) })
                                restRow(String(localized: "Disturbances"), day.disturbances.map { "\($0)" })
                            } else {
                                Text("No scored night yet.")
                                    .font(StrandFont.caption)
                                    .foregroundStyle(StrandPalette.textSecondary)
                            }
                        }
                    }
                    SimpleSheetLink(title: String(localized: "See your sleep"), icon: "bed.double", route: .sleep)
                    NavigationLink {
                        ScoringGuideView(initialSection: .rest, onClose: onClose)
                    } label: {
                        SimpleSheetLinkRow(title: String(localized: "How Rest is scored"), icon: "info.circle")
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, NoopMetrics.screenHPadding)
                .padding(.vertical, NoopMetrics.space4)
            }
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .navigationTitle(Text("Rest"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .tabRouteDestinations()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onClose).foregroundStyle(StrandPalette.accent)
                }
            }
        }
    }

    /// A label and value; a missing value hides the row rather than showing a placeholder.
    @ViewBuilder private func restRow(_ label: String, _ value: String?) -> some View {
        if let value {
            HStack {
                Text(verbatim: label).font(StrandFont.body).foregroundStyle(StrandPalette.textSecondary)
                Spacer()
                Text(verbatim: value).font(StrandFont.bodyNumber).foregroundStyle(StrandPalette.textPrimary)
            }
        }
    }
}

// MARK: - Shared pieces

/// The big number and its name at the top of a score sheet.
struct SimpleScoreHeader: View {
    let value: String?
    let name: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: NoopMetrics.space2) {
            Text(verbatim: value ?? "—")
                .font(StrandFont.number(34))
                .foregroundStyle(StrandPalette.textPrimary)
            Text(verbatim: name)
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
        }
    }
}

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

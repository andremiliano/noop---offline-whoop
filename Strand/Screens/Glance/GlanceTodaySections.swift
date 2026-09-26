import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

// The sections of the Glance Today (#2463). Each takes the figures Today has already resolved, or reads
// them through the same resolver another screen uses (`BodyVitalSigns` for the Health Monitor, the Stress
// tab's own day curve), so a Glance section and the screen it opens cannot disagree.

// MARK: - Score card

/// One fact in the score card's plan row: what to aim for, as a label and a value.
struct GlancePlanItem: Identifiable {
    let icon: String
    let tint: Color
    let label: String
    let value: String
    var id: String { label }
}

/// The three rings, with the day's synthesis and Effort target beneath them in the same card.
struct GlanceScoreCard<Rings: View>: View {
    let synthesis: String
    /// A second line under the synthesis — the calibration reason or the calm-day Effort note — or nil.
    let note: String?
    /// The day's plan (Effort to aim for, tonight's sleep), empty for none.
    let plan: [GlancePlanItem]
    let effort: Double?
    let band: ClosedRange<Double>?
    let scale: EffortScale
    /// The target applies to today only; a past day shows the synthesis alone.
    let showsTarget: Bool
    let cardOpacity: Double
    @ViewBuilder let rings: () -> Rings

    private var decimals: Int { scale == .whoop ? 1 : 0 }

    var body: some View {
        VStack(spacing: 0) {
            rings()
                .padding(.vertical, NoopMetrics.space4)
                .padding(.horizontal, NoopMetrics.space3)
            Rectangle().fill(StrandPalette.hairline).frame(height: 1)
            VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                Text("Synthesis").strandOverline()
                Text(verbatim: synthesis)
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let note {
                    Text(verbatim: note)
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !plan.isEmpty {
                    HStack(spacing: NoopMetrics.space2) {
                        ForEach(plan) { item in
                            HStack(spacing: NoopMetrics.space2) {
                                Image(systemName: item.icon)
                                    .font(StrandFont.subhead)
                                    .foregroundStyle(item.tint)
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(verbatim: item.label)
                                        .font(StrandFont.caption)
                                        .foregroundStyle(StrandPalette.textSecondary)
                                    Text(verbatim: item.value)
                                        .font(StrandFont.number(17))
                                        .foregroundStyle(StrandPalette.textPrimary)
                                }
                                .lineLimit(1).minimumScaleFactor(0.75)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, NoopMetrics.space3)
                            .padding(.vertical, NoopMetrics.space2)
                            .frame(maxWidth: .infinity)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(StrandPalette.surfaceInset.opacity(0.6)))
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(.top, NoopMetrics.space1)
                }
                if showsTarget {
                    NavigationLink(value: GlanceScoreRoute.effort) {
                        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                            // The range itself is in the plan row above; stating it here too would be
                            // the same fact twice.
                            EffortTargetBar(axisMax: EffortTarget.axisMax(scale), band: band, effort: effort)
                            EffortTargetStatusText(standing: EffortTarget.standing(effort: effort, band: band),
                                                   hasBand: band != nil, decimals: decimals)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityHint(Text("Opens the trend and readings"))
                    .padding(.top, NoopMetrics.space2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(NoopMetrics.cardPadding)
        }
        .background(NoopPanelSurface(cornerRadius: 26, elevated: true, surfaceOpacity: cardOpacity))
    }
}

// MARK: - Stress

/// Today's stress through the waking hours: the Stress tab's own line, with its highest, lowest and
/// average hour. Opens the Stress tab.
struct GlanceStressCard: View {
    let hours: [DaytimeStress.HourPoint]

    var body: some View {
        NavigationLink(value: TabRoute.stress) {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                HStack {
                    Text("Stress through the day")
                        .font(StrandFont.headline)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Spacer()
                    GlanceChevron()
                }
                let levels = hours.compactMap(\.level)
                if levels.isEmpty {
                    // The honest blank: only waking hours score and an hour needs enough heart rate, so
                    // early morning is empty by construction rather than by failure.
                    Text("Calibrating")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .frame(maxWidth: .infinity, minHeight: 60, alignment: .center)
                } else {
                    DaytimeLoadLine(hours: hours)
                    HStack(spacing: 0) {
                        stat(String(localized: "Highest"), levels.max())
                        stat(String(localized: "Lowest"), levels.min())
                        stat(String(localized: "Average"), levels.reduce(0, +) / Double(levels.count))
                    }
                }
            }
            .padding(NoopMetrics.cardPadding)
            .background(NoopPanelSurface(cornerRadius: NoopMetrics.cardRadius))
            .contentShape(Rectangle())
        }
        .buttonStyle(LiquidPressStyle())
    }

    private func stat(_ label: String, _ v: Double?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: v.map { String(format: "%.1f", locale: AppLanguage.activeLocale, $0) } ?? "—")
                .font(StrandFont.number(20))
                .foregroundStyle(StrandPalette.textPrimary)
            Text(verbatim: label).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Health Monitor

/// One Health Monitor tile: the vital, its value, what that means in plain words, and a small gauge with
/// the normal range shaded and today marked in it.
struct GlanceMonitorTile: View {
    let icon: String
    let label: String
    let value: String?
    let status: GlanceStatus
    /// The gauge's marker and shaded normal range, each 0 (bottom) … 1 (top), or nil without a trend.
    let gauge: Gauge?
    let tint: Color

    struct Gauge: Equatable {
        let marker: Double
        let band: ClosedRange<Double>?
    }

    var body: some View {
        HStack(alignment: .top, spacing: NoopMetrics.space2) {
            VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                Label {
                    Text(verbatim: label).font(StrandFont.subhead)
                } icon: {
                    Image(systemName: icon)
                }
                .foregroundStyle(StrandPalette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.8)
                Text(verbatim: value ?? String(localized: "No data"))
                    .font(StrandFont.number(value == nil ? 20 : 24))
                    .foregroundStyle(value == nil ? StrandPalette.textTertiary : StrandPalette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.55)
                Label {
                    Text(verbatim: status.text).font(StrandFont.caption.weight(.medium))
                } icon: {
                    Image(systemName: status.icon)
                }
                .foregroundStyle(status.color)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            GeometryReader { geo in
                let h = geo.size.height
                ZStack(alignment: .bottom) {
                    Capsule().fill(StrandPalette.surfaceInset)
                    if let band = gauge?.band {
                        Capsule()
                            .fill(StrandPalette.statusPositive.opacity(0.35))
                            .frame(height: max(6, CGFloat(band.upperBound - band.lowerBound) * h))
                            .offset(y: -CGFloat(band.lowerBound) * h)
                    }
                    if let marker = gauge?.marker {
                        Circle()
                            .strokeBorder(tint, lineWidth: 2.5)
                            .background(Circle().fill(StrandPalette.surfaceBase))
                            .frame(width: 12, height: 12)
                            .offset(y: -CGFloat(max(0, min(1, marker))) * (h - 12))
                    }
                }
            }
            .frame(width: 12)
            .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .padding(NoopMetrics.space4)
        .background(NoopPanelSurface(cornerRadius: NoopMetrics.cardRadius))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// `value` and `range` placed on one axis spanning the recent `values`, the value and the range, so
    /// the marker sits inside the shaded band exactly when the value is inside the range.
    static func gauge(value: Double?, values: [Double], range: ClosedRange<Double>?) -> Gauge? {
        guard let value else { return nil }
        var all = values + [value]
        if let range { all += [range.lowerBound, range.upperBound] }
        guard let lo = all.min(), let hi = all.max(), hi > lo else { return nil }
        let f = { (x: Double) in (x - lo) / (hi - lo) }
        return Gauge(marker: f(value), band: range.map { f($0.lowerBound)...f($0.upperBound) })
    }
}

/// The vitals grid: every vital the Health tab resolves that has a value, in plain words, plus last
/// night's sleep. Each tile opens its own plain-language page.
struct GlanceHealthMonitor: View {
    @EnvironmentObject private var repo: Repository
    /// Last night's time asleep, from the day row the Rest ring reads.
    let sleepMinutes: Double?
    let dayKey: String

    @State private var allReadings: [BodyVitalReading] = []
    private let units = GlanceUnitPrefs()

    var body: some View {
        let readings = allReadings.filter(GlanceVitalInputs.showsOnGlance)
        LazyVGrid(columns: [GridItem(.flexible(), spacing: NoopMetrics.gap),
                            GridItem(.flexible(), spacing: NoopMetrics.gap)],
                  spacing: NoopMetrics.gap) {
            ForEach(readings) { r in
                NavigationLink(value: GlanceScoreRoute.vital(r.key)) {
                    GlanceMonitorTile(icon: GlanceVitalInputs.icon(r.key), label: r.label, value: r.formattedValue,
                                      status: .vital(r),
                                      gauge: GlanceMonitorTile.gauge(value: r.value, values: r.sparkline ?? [], range: r.normalRange),
                                      tint: r.metricColor)
                }
                .buttonStyle(LiquidPressStyle())
            }
            let sleep = GlanceHistory.trend(days: repo.days, through: dayKey, value: sleepMinutes, \.totalSleepMin)
            NavigationLink(value: GlanceScoreRoute.rest) {
                GlanceMonitorTile(icon: "bed.double.fill", label: String(localized: "Sleep"),
                                  value: sleepMinutes.map { GlanceDuration.text(minutes: $0) },
                                  status: .usual(sleep.result),
                                  gauge: GlanceMonitorTile.gauge(value: sleepMinutes, values: sleep.values, range: sleep.result.band),
                                  tint: StrandPalette.restLine)
            }
            .buttonStyle(LiquidPressStyle())
        }
        .task(id: GlanceVitalInputs.reloadKey(repo, units: units)) {
            allReadings = await GlanceVitalInputs.loadReadings(repo, units: units)
        }
    }
}

// MARK: - Timeline

/// The day in order: its workouts and the night that ended it, each with its score.
struct GlanceTimeline: View {
    /// The day's workouts, newest first — the list Today shows.
    let workouts: [WorkoutRow]
    let scale: EffortScale
    let night: CachedSleepSession?
    let restScore: Double?

    var body: some View {
        VStack(spacing: NoopMetrics.gap) {
            ForEach(workouts, id: \.startTs) { w in
                GlanceWorkoutTimelineRow(workout: w, scale: scale)
            }
            if let night {
                NavigationLink(value: GlanceScoreRoute.rest) {
                    GlanceTimelineRow(glyph: .sleep, badge: GlanceFormat.whole(restScore),
                                      tint: StrandPalette.restLine, title: String(localized: "Sleep"),
                                      subtitle: "\(GlanceFormat.time(night.startTs)) – \(GlanceFormat.time(night.endTs))")
                }
                .buttonStyle(LiquidPressStyle())
            }
            if workouts.isEmpty && night == nil {
                Text("No workouts or sleep recorded.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(NoopMetrics.cardPadding)
                    .background(NoopPanelSurface(cornerRadius: NoopMetrics.cardRadius))
            }
        }
    }
}

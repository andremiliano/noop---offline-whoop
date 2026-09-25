import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

// The sections of the Glance Today (#2463). Each takes the figures Today has already resolved, or reads
// them through the same resolver another screen uses (`BodyVitalSigns` for the Health Monitor, the Stress
// tab's own day curve), so a Glance section and the screen it opens cannot disagree.

// MARK: - Score card

/// The three rings, with the day's synthesis and Effort target beneath them in the same card.
struct GlanceScoreCard<Rings: View>: View {
    let synthesis: String
    /// A second line under the synthesis — the calibration reason or the calm-day Effort note — or nil.
    let note: String?
    let effort: Double?
    let band: ClosedRange<Double>?
    let scale: EffortScale
    /// The target applies to today only; a past day shows the synthesis alone.
    let showsTarget: Bool
    let cardOpacity: Double
    let onOpenEffort: () -> Void
    @ViewBuilder let rings: () -> Rings

    private var decimals: Int { scale == .whoop ? 1 : 0 }

    private func rangeText(_ b: ClosedRange<Double>) -> String {
        let f = "%.\(decimals)f"
        return String(format: "\(f)–\(f)", locale: AppLanguage.activeLocale, b.lowerBound, b.upperBound)
    }

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
                if showsTarget {
                    Button(action: onOpenEffort) {
                        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("Today's Effort target").strandOverline()
                                Spacer()
                                if let band {
                                    Text(verbatim: rangeText(band))
                                        .font(StrandFont.number(15))
                                        .foregroundStyle(StrandPalette.textPrimary)
                                }
                            }
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

/// One Health Monitor tile: the vital, its value, its in-range word, and a gauge placing today among the
/// recent days.
struct GlanceMonitorTile: View {
    let icon: String
    let label: String
    let value: String?
    let status: GlanceStatus
    /// Today's value between the recent days' lowest (0) and highest (1), or nil without a trend.
    let position: Double?
    let tint: Color

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
                ZStack(alignment: .bottom) {
                    Capsule().fill(StrandPalette.surfaceInset)
                    if let position {
                        Circle()
                            .strokeBorder(tint, lineWidth: 2.5)
                            .background(Circle().fill(StrandPalette.surfaceBase))
                            .frame(width: 12, height: 12)
                            .offset(y: -CGFloat(max(0, min(1, position))) * (geo.size.height - 12))
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

    /// `last` between `values`' lowest and highest, or nil with fewer than two distinct values.
    static func position(of last: Double?, in values: [Double]) -> Double? {
        guard let last, let lo = values.min(), let hi = values.max(), hi > lo else { return nil }
        return (last - lo) / (hi - lo)
    }
}

/// The vitals grid: every vital the Health tab resolves, in its words, plus last night's sleep. Each tile
/// opens the vital's own page; the sleep tile opens the Rest page.
struct GlanceHealthMonitor: View {
    @EnvironmentObject private var repo: Repository
    /// Last night's time asleep, from the day row the Rest ring reads.
    let sleepMinutes: Double?
    let dayKey: String
    let onOpenSleep: () -> Void

    @State private var vitals = GlanceVitalInputs()
    private let units = GlanceUnitPrefs()

    var body: some View {
        let readings = vitals.readings(repo, temperatureUnit: units.temperatureUnit,
                                       skinTempPreferred: units.skinTempPreferred)
        LazyVGrid(columns: [GridItem(.flexible(), spacing: NoopMetrics.gap),
                            GridItem(.flexible(), spacing: NoopMetrics.gap)],
                  spacing: NoopMetrics.gap) {
            ForEach(readings) { r in
                NavigationLink(value: GlanceVitalInputs.route(r.key)) {
                    GlanceMonitorTile(icon: GlanceVitalInputs.icon(r.key), label: r.label, value: r.formattedValue,
                                      status: .vital(r),
                                      position: GlanceMonitorTile.position(of: r.value, in: r.sparkline ?? []),
                                      tint: r.metricColor)
                }
                .buttonStyle(LiquidPressStyle())
            }
            let sleep = GlanceHistory.trend(days: repo.days, through: dayKey, value: sleepMinutes, \.totalSleepMin)
            Button(action: onOpenSleep) {
                GlanceMonitorTile(icon: "bed.double.fill", label: String(localized: "Sleep"),
                                  value: sleepMinutes.map { GlanceDuration.text(minutes: $0) },
                                  status: .usual(sleep.result),
                                  position: GlanceMonitorTile.position(of: sleepMinutes, in: sleep.values),
                                  tint: StrandPalette.restLine)
            }
            .buttonStyle(LiquidPressStyle())
        }
        .task { vitals = await GlanceVitalInputs.load(repo) }
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
    let onOpenNight: () -> Void

    var body: some View {
        VStack(spacing: NoopMetrics.gap) {
            ForEach(workouts, id: \.startTs) { w in
                NavigationLink(value: TabRoute.workouts) {
                    GlanceTimelineRow(glyph: .workout(w.sport),
                                      badge: w.strain.map { UnitFormatter.effortDisplay($0, scale: scale) },
                                      tint: StrandPalette.effortColor,
                                      title: WorkoutSource.displaySport(w.sport),
                                      subtitle: GlanceFormat.time(w.startTs))
                }
                .buttonStyle(LiquidPressStyle())
            }
            if let night {
                Button(action: onOpenNight) {
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

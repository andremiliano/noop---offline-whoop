import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

// The Glance score pages (#2463): what a Charge, Effort or Rest ring opens. Each page takes the score its
// ring shows from the caller, so the ring and the page cannot disagree, and reads everything else through
// the resolvers the rest of the app already uses (`ChargeBreakdownWiring`, `BodyVitalSigns`,
// `Repository.workoutZoneMinutes`, the day rows). Trend rows compare a value with the wearer's own recent
// days (`UsualRange`), or, for a vital, with the baseline the Health tab bands it against.
//
// A page is the first hop from Today, so it is pushed as a value (`GlanceScoreRoute`) and rides the tab's
// `NavigationPath`; its own links are deeper hops and push closure destinations (`TabRoute.destination`),
// the convention `TabRoute` documents.

/// The score page a Glance ring, tile or timeline row opens. Registered once, by Today.
enum GlanceScoreRoute: Hashable {
    case charge
    case effort
    case rest
    /// One vital's plain-language page, by `BodyVitalReading.key`.
    case vital(String)
}

// MARK: - Shared scaffold

/// A score page: the tinted sky behind a scrolling column, with the scoring guide one tap away.
struct GlanceScorePage<Content: View>: View {
    let title: String
    let tint: Color
    /// The scoring-guide section the ⓘ opens, or nil for a page with no guide (a vital).
    let guide: ScoreSection?
    @ViewBuilder let content: () -> Content

    @State private var showGuide = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopMetrics.gap) {
                content()
                Color.clear.frame(height: NoopMetrics.tabBarClearance)
            }
            .padding(.horizontal, NoopMetrics.screenHPadding)
            #if os(macOS)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
            #endif
        }
        .background(alignment: .top) { GlanceScoreBackdrop(tint: tint) }
        .navigationTitle(Text(verbatim: title))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if guide != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button { showGuide = true } label: { Image(systemName: "info.circle") }
                        .accessibilityLabel(Text("How it is scored"))
                }
            }
        }
        .sheet(isPresented: $showGuide) {
            NavigationStack { ScoringGuideView(initialSection: guide, onClose: { showGuide = false }) }
        }
    }
}

// MARK: - History

/// Trend inputs for one metric: the sparkline values ending on the displayed value, and that value
/// against the prior days.
enum GlanceHistory {
    /// Days in the trend window.
    static let windowDays = 30

    /// `value` (the figure the page displays for `dayKey`) against the `windowDays` days before it.
    static func trend(_ points: [(day: String, value: Double)], through dayKey: String,
                      value: Double?) -> (values: [Double], result: UsualRange.Result) {
        let prior = points.filter { $0.day < dayKey }.sorted { $0.day < $1.day }.suffix(windowDays).map(\.value)
        var values = Array(prior)
        if let value { values.append(value) }
        return (Array(values.suffix(windowDays)), UsualRange.evaluate(value: value, history: Array(prior)))
    }

    /// One column of the day rows up to and including `dayKey`, oldest first — a trend page's series.
    static func points(days: [DailyMetric], through dayKey: String,
                       _ column: (DailyMetric) -> Double?) -> [(day: String, value: Double)] {
        days.compactMap { d in d.day <= dayKey ? column(d).map { (d.day, $0) } : nil }.sorted { $0.day < $1.day }
    }

    /// `trend` over one column of the day rows.
    static func trend(days: [DailyMetric], through dayKey: String, value: Double?,
                      _ column: (DailyMetric) -> Double?) -> (values: [Double], result: UsualRange.Result) {
        trend(days.compactMap { d in column(d).map { (d.day, $0) } }, through: dayKey, value: value)
    }

    /// The main night that ended on `dayKey`: the longest session whose wake falls on that logical day.
    @MainActor
    static func night(_ sleeps: [CachedSleepSession], dayKey: String) -> CachedSleepSession? {
        sleeps
            .filter { Repository.logicalDayKey(Date(timeIntervalSince1970: TimeInterval($0.endTs))) == dayKey }
            .max { ($0.endTs - $0.startTs) < ($1.endTs - $1.startTs) }
    }
}

// MARK: - Vitals

/// The vital readings exactly as the Health tab resolves them — same rows, same unit and lead-with
/// preferences, same per-night flags — so a vital shown on a Glance surface matches the Health tab.
struct GlanceVitalInputs {
    var spo2CandidateByDay: [String: Double] = [:]
    var hrvOverCountByDay: [String: Double] = [:]

    /// The two per-night maps `VitalsSection` loads, loaded the same way.
    static func load(_ repo: Repository) async -> GlanceVitalInputs {
        var out = GlanceVitalInputs()
        let oc = await repo.exploreSeries(key: "hrv_rr_overcount", source: "my-whoop", days: 14)
        out.hrvOverCountByDay = Dictionary(oc.map { ($0.day, $0.value) }, uniquingKeysWith: { a, _ in a })
        if PuffinExperiment.spo2CandidateDisplayEnabled {
            let pts = await repo.exploreSeries(key: "spo2_candidate", source: "my-whoop", days: 14)
            out.spo2CandidateByDay = Dictionary(pts.map { ($0.day, $0.value) }, uniquingKeysWith: { a, _ in a })
        }
        return out
    }

    /// Load the per-night maps and resolve the readings once, for a view to keep in `@State` rather than
    /// re-resolving on every render.
    @MainActor
    static func loadReadings(_ repo: Repository, units: GlanceUnitPrefs) async -> [BodyVitalReading] {
        await load(repo).readings(repo, temperatureUnit: units.temperatureUnit,
                                  skinTempPreferred: units.skinTempPreferred)
    }

    /// Refreshes when the data or a unit preference changes.
    @MainActor
    static func reloadKey(_ repo: Repository, units: GlanceUnitPrefs) -> String {
        "\(repo.refreshSeq)-\(units.temperatureUnit)-\(units.skinTempPreferred.rawValue)"
    }

    @MainActor
    func readings(_ repo: Repository, temperatureUnit: TemperatureUnit,
                  skinTempPreferred: SkinTempDisplay.Kind) -> [BodyVitalReading] {
        BodyVitalSigns.readings(sourceRows: repo.vitalMetricRows, temperatureUnit: temperatureUnit,
                                spo2CandidateByDay: spo2CandidateByDay,
                                hrvOverCountByDay: hrvOverCountByDay,
                                skinTempPreferred: skinTempPreferred)
    }

    /// Symbol and metric page for a vital reading's key.
    static func icon(_ key: String) -> String {
        switch key {
        case "resp":    return "lungs.fill"
        case "spo2", "spo2raw": return "drop.fill"
        case "rhr":     return "heart.fill"
        case "hrv":     return "waveform.path.ecg"
        case "skin":    return "thermometer.medium"
        default:        return "circle"
        }
    }

    /// Whether a reading earns a Glance tile: it has a value, and it is a calibrated measure. Raw SpO₂ is
    /// a sensor count with no meaning to read at a glance; it stays on the Health tab.
    static func showsOnGlance(_ r: BodyVitalReading) -> Bool {
        r.value != nil && r.key != "spo2raw"
    }

    /// One plain sentence on what a vital is and how to read it.
    static func explainer(_ key: String) -> String {
        switch key {
        case "resp":
            return String(localized: "Breaths per minute while you sleep. It barely changes from night to night, so a clear rise is worth noticing: it can come with illness or a hard day.")
        case "spo2":
            return String(localized: "How much oxygen your blood carries while you sleep. Most people sit between 95% and 100%.")
        case "rhr":
            return String(localized: "Your heart rate at rest while you sleep. Lower than your normal usually means well recovered; a rise can follow hard training, alcohol, stress or illness.")
        case "hrv":
            return String(localized: "How much the time between heartbeats varies while you sleep. Higher than your normal usually means well recovered. Compare it with yourself, not with other people.")
        case "skin":
            return String(localized: "Your wrist temperature overnight. The number itself matters less than change from your own normal: a rise can come with illness, alcohol or a warm room.")
        default:
            return ""
        }
    }

    static func route(_ key: String) -> TabRoute {
        switch key {
        case "resp":    return .metric("resp_rate")
        case "spo2", "spo2raw": return .metric("spo2")
        case "rhr":     return .metric("rhr")
        case "hrv":     return .metric("hrv")
        case "skin":    return .metric("skin_temp")
        default:        return .health
        }
    }
}

/// The unit preferences every vital read-out honours, read once.
struct GlanceUnitPrefs: DynamicProperty {
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.skinTempDisplayKey) private var skinTempDisplayRaw = ""
    @AppStorage(UnitPrefs.temperatureKey) private var temperatureRaw = ""

    var temperatureUnit: TemperatureUnit {
        UnitPrefs.resolveTemperature(system: UnitSystem(rawValue: unitSystemRaw) ?? .metric, override: temperatureRaw)
    }
    var skinTempPreferred: SkinTempDisplay.Kind { SkinTempDisplay.Kind(rawValue: skinTempDisplayRaw) ?? .absolute }
}

/// A trend row for one vital reading, linked to its metric page.
struct GlanceVitalTrendRow: View {
    let reading: BodyVitalReading

    var body: some View {
        NavigationLink { GlanceVitalPage(key: reading.key) } label: {
            GlanceTrendRow(icon: GlanceVitalInputs.icon(reading.key), title: reading.label,
                           value: reading.formattedValue, status: .vital(reading),
                           values: reading.sparkline ?? [], band: reading.normalRange, tint: reading.metricColor)
        }
        .buttonStyle(LiquidPressStyle())
    }
}

/// One vital in plain words: the value and what it means, your normal range and where it came from,
/// the recent nights against that range, and what the vital is. The full technical page is one tap on.
struct GlanceVitalPage: View {
    @EnvironmentObject private var repo: Repository
    let key: String

    @State private var readings: [BodyVitalReading] = []
    private let units = GlanceUnitPrefs()

    var body: some View {
        let reading = readings.first { $0.key == key }
        GlanceScorePage(title: reading?.label ?? "", tint: reading?.metricColor ?? StrandPalette.accent, guide: nil) {
            if let reading {
                VStack(spacing: NoopMetrics.space2) {
                    Image(systemName: GlanceVitalInputs.icon(key))
                        .font(.system(size: 28))
                        .foregroundStyle(reading.metricColor)
                    Text(verbatim: reading.formattedValue ?? String(localized: "No data"))
                        .font(StrandFont.number(52))
                        .foregroundStyle(StrandPalette.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.5)
                    GlanceStatusLine(status: .vital(reading))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, NoopMetrics.space6)

                if let range = reading.normalRange {
                    VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                        Text(verbatim: reading.banding.basis == .personal
                             ? String(localized: "Your normal range") : String(localized: "Usual adult range"))
                            .strandOverline()
                        Text(verbatim: rangeText(reading, range))
                            .font(StrandFont.number(24))
                            .foregroundStyle(StrandPalette.textPrimary)
                        Text(verbatim: basisLine(reading))
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(NoopMetrics.cardPadding)
                    .background(NoopPanelSurface(cornerRadius: NoopMetrics.cardRadius))
                }

                VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                    Text("What it is").strandOverline()
                    Text(verbatim: GlanceVitalInputs.explainer(key))
                        .font(StrandFont.body)
                        .foregroundStyle(StrandPalette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(NoopMetrics.cardPadding)
                .background(NoopPanelSurface(cornerRadius: NoopMetrics.cardRadius))

                GlanceTrendSections(series: GlanceTrendSeries(
                    title: reading.label, icon: GlanceVitalInputs.icon(key), tint: reading.metricColor,
                    points: reading.series, format: { [unit = reading.unit, f = reading.format] in "\(f($0)) \(unit)" },
                    band: reading.normalRange, detailsRoute: GlanceVitalInputs.route(key)))
            }
        }
        .task(id: GlanceVitalInputs.reloadKey(repo, units: units)) {
            readings = await GlanceVitalInputs.loadReadings(repo, units: units)
        }
    }

    /// "32.0 – 33.1 °C", in the reading's own display format.
    private func rangeText(_ r: BodyVitalReading, _ range: ClosedRange<Double>) -> String {
        [r.format(range.lowerBound), "–", r.format(range.upperBound), r.unit].joined(separator: " ")
    }

    /// Where the range comes from, in one sentence.
    private func basisLine(_ r: BodyVitalReading) -> String {
        if r.banding.basis == .personal {
            return String(localized: "Learned from your last \(r.banding.nights) nights. Most of your nights fall inside it.")
        }
        if r.key == "spo2" {
            return String(localized: "The range most healthy adults sit in.")
        }
        return String(localized: "NOOP is still learning your own normal (\(r.banding.nights) of 14 nights), so this is the range most adults sit in for now. Being outside it is common and not a concern on its own.")
    }
}

// MARK: - Charge

/// What the Charge ring opens: the score, the day's synthesis, what shaped it, and the vitals behind it.
struct GlanceChargePage: View {
    @EnvironmentObject private var repo: Repository
    /// The Charge the ring shows, and its state word ("Solid", "Last night", "Calibrating").
    let charge: Double?
    let stateLabel: String
    /// The synthesis sentence Today shows.
    let synthesis: String
    /// The scored night the breakdown reads — the same row classic Today breaks down.
    let breakdownRow: DailyMetric?
    let restScore: Double?
    let date: Date
    let dayKey: String

    @State private var readings: [BodyVitalReading] = []
    private let units = GlanceUnitPrefs()

    var body: some View {
        GlanceScorePage(title: String(localized: "Charge"), tint: tint, guide: .charge) {
            GlanceScoreHero(subtitle: GlanceFormat.dayTitle(date),
                            score: charge, tint: tint, caption: stateLabel)
            GlanceSynthesisCard(text: synthesis)
            if charge == nil {
                NavigationLink { StrapSetupGuideView() } label: {
                    GlanceLinkRow(title: String(localized: "Why is there no Charge?"), icon: "exclamationmark.circle")
                }
                .buttonStyle(.plain)
            }
            breakdown
            GlanceSectionTitle(title: String(localized: "Trends"))
            let chargeTrend = GlanceHistory.trend(days: repo.days, through: dayKey, value: charge, \.recovery)
            NavigationLink {
                GlanceTrendDetailPage(series: GlanceTrendSeries(
                    title: String(localized: "Charge"), icon: "heart.circle.fill", tint: StrandPalette.chargeColor,
                    points: GlanceHistory.points(days: repo.days, through: dayKey, \.recovery),
                    format: { "\(Int($0.rounded()))%" }, detailsRoute: .metric(HeroRingMetric.charge)))
            } label: {
                GlanceTrendRow(icon: "heart.circle.fill", title: String(localized: "Charge"),
                               value: GlanceFormat.whole(charge, unit: "%"), status: .usual(chargeTrend.result),
                               values: chargeTrend.values, band: chargeTrend.result.band, tint: StrandPalette.chargeColor)
            }
            .buttonStyle(LiquidPressStyle())
            ForEach(readings.filter(GlanceVitalInputs.showsOnGlance)) { reading in
                GlanceVitalTrendRow(reading: reading)
            }
        }
        .task(id: GlanceVitalInputs.reloadKey(repo, units: units)) {
            readings = await GlanceVitalInputs.loadReadings(repo, units: units)
        }
    }

    private var tint: Color { charge.map { StrandPalette.recoveryColor($0) } ?? StrandPalette.chargeColor }

    @ViewBuilder private var breakdown: some View {
        let result = breakdownRow.flatMap {
            ChargeBreakdownWiring.breakdown(days: repo.days, row: $0, sleepPerfPercent: restScore,
                                            hrvBaselineEpoch: Baselines.hrvBaselineEpoch())
        }
        if let result, !result.drivers.isEmpty {
            // No section title: the breakdown carries its own "What shaped it" header.
            // No `skinTempRel`: the skin-temperature driver row already states the deviation, and the
            // relative row would show the same fact a second time in different words.
            ChargeBreakdownSection(drivers: result.drivers, confidence: result.confidence)
                .padding(NoopMetrics.cardPadding)
                .background(NoopPanelSurface(cornerRadius: NoopMetrics.cardRadius))
        }
    }
}

// MARK: - Effort

/// What the Effort ring opens: the score against today's target, the day's workouts, time in each heart
/// rate zone, and Effort over recent days.
struct GlanceEffortPage: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    /// The Effort the ring shows, already on `scale`.
    let effort: Double?
    let band: ClosedRange<Double>?
    let scale: EffortScale
    /// The window the ring's Effort covers, so zone time and the score describe the same stretch.
    let from: Int
    let to: Int
    /// The day's workouts, newest first — the list Today shows.
    let workouts: [WorkoutRow]
    /// Today's calories and steps as Today's own tiles resolve them.
    let caloriesText: String?
    let stepsText: String?
    let date: Date
    let dayKey: String

    @State private var zoneMinutes: [Double]?

    private var decimals: Int { scale == .whoop ? 1 : 0 }

    var body: some View {
        GlanceScorePage(title: String(localized: "Effort"), tint: StrandPalette.effortColor, guide: .effort) {
            GlanceScoreHero(subtitle: GlanceFormat.dayTitle(date),
                            score: effort, tint: StrandPalette.effortColor,
                            maxValue: EffortTarget.axisMax(scale), decimals: decimals,
                            caption: band.map { String(localized: "Target Effort: \(rangeText($0))") },
                            target: band)
            HStack(spacing: NoopMetrics.gap) {
                GlanceStatTile(icon: "flame.fill", label: String(localized: "Calories"), value: caloriesText)
                GlanceStatTile(icon: "figure.walk", label: String(localized: "Steps"), value: stepsText)
            }
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                Text("Today's Effort target").strandOverline()
                EffortTargetBar(axisMax: EffortTarget.axisMax(scale), band: band, effort: effort, decimals: decimals)
                EffortTargetStatusText(standing: EffortTarget.standing(effort: effort, band: band),
                                       hasBand: band != nil, decimals: decimals)
            }
            .padding(NoopMetrics.cardPadding)
            .background(NoopPanelSurface(cornerRadius: NoopMetrics.cardRadius))

            if !workouts.isEmpty {
                GlanceSectionTitle(title: String(localized: "Timeline"))
                ForEach(workouts, id: \.startTs) { w in
                    GlanceWorkoutTimelineRow(workout: w, scale: scale)
                }
            }

            GlanceSectionTitle(title: String(localized: "Heart Rate Zones"))
            zones

            GlanceSectionTitle(title: String(localized: "Trends"))
            let trend = GlanceHistory.trend(days: repo.days, through: dayKey, value: effort) {
                $0.strain.map { UnitFormatter.effortValue($0, scale: scale) }
            }
            NavigationLink {
                GlanceTrendDetailPage(series: GlanceTrendSeries(
                    title: String(localized: "Effort"), icon: "bolt.fill", tint: StrandPalette.effortColor,
                    points: GlanceHistory.points(days: repo.days, through: dayKey) {
                        $0.strain.map { UnitFormatter.effortValue($0, scale: scale) }
                    },
                    format: { [decimals] in GlanceFormat.score($0, decimals: decimals) },
                    detailsRoute: .metric(HeroRingMetric.effort)))
            } label: {
                GlanceTrendRow(icon: "bolt.fill", title: String(localized: "Effort"),
                               value: effort.map { GlanceFormat.score($0, decimals: decimals) },
                               status: .usual(trend.result), values: trend.values, band: trend.result.band,
                               tint: StrandPalette.effortColor)
            }
            .buttonStyle(LiquidPressStyle())
            TrainingLoadCard(days: repo.days)
        }
        .task { zoneMinutes = await repo.workoutZoneMinutes(from: from, to: to, zoneSet: profile.hrZoneSet) }
    }

    @ViewBuilder private var zones: some View {
        if let z = zoneMinutes, z.count == 5, z.reduce(0, +) > 0 {
            let longest = z.max() ?? 0
            let set = profile.hrZoneSet
            ForEach((0..<5).reversed(), id: \.self) { i in
                GlanceZoneRow(zone: i + 1, minutes: z[i], longest: longest,
                              bpmRange: set.zones.count == 5
                                ? "\(Int(set.zones[i].lower.rounded()))–\(Int(set.zones[i].upper.rounded())) bpm" : nil)
            }
        } else {
            Text("No heart-rate zone time recorded today yet.")
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(NoopMetrics.cardPadding)
                .background(NoopPanelSurface(cornerRadius: NoopMetrics.cardRadius))
        }
    }

    private func rangeText(_ b: ClosedRange<Double>) -> String {
        let f = "%.\(decimals)f"
        return String(format: "\(f)–\(f)", locale: AppLanguage.activeLocale, b.lowerBound, b.upperBound)
    }
}

// MARK: - Rest

/// What the Rest ring opens: the score, when the night started and ended, and the night's parts against
/// recent nights.
struct GlanceRestPage: View {
    @EnvironmentObject private var repo: Repository
    /// The Rest the ring shows.
    let restScore: Double?
    /// The same day row the ring reads.
    let day: DailyMetric?
    let date: Date
    let dayKey: String

    @State private var restPoints: [(day: String, value: Double)] = []

    var body: some View {
        GlanceScorePage(title: String(localized: "Rest"), tint: StrandPalette.restColor, guide: .rest) {
            GlanceScoreHero(subtitle: GlanceFormat.dayTitle(date),
                            score: restScore, tint: StrandPalette.restColor)
            let night = GlanceHistory.night(repo.sleeps, dayKey: dayKey)
            HStack(spacing: NoopMetrics.gap) {
                GlanceStatTile(icon: "bed.double.fill", label: String(localized: "Fell asleep"),
                               value: night.map { GlanceFormat.time($0.startTs) })
                GlanceStatTile(icon: "sun.horizon.fill", label: String(localized: "Woke up"),
                               value: night.map { GlanceFormat.time($0.endTs) })
            }
            NavigationLink { TabRoute.sleep.destination } label: {
                GlanceLinkRow(title: String(localized: "See your sleep"), icon: "bed.double")
            }
            .buttonStyle(.plain)

            GlanceSectionTitle(title: String(localized: "Trends"))
            let rest = GlanceHistory.trend(restPoints, through: dayKey, value: restScore)
            trendLink(HeroRingMetric.rest, icon: "moon.zzz.fill", title: String(localized: "Rest"),
                      value: GlanceFormat.whole(restScore, unit: "%"), rest,
                      points: restPoints.filter { $0.day <= dayKey }, format: { "\(Int($0.rounded()))%" })
            durationRow("sleep_total_min", icon: "clock.fill", title: String(localized: "Time asleep"), \.totalSleepMin)
            durationRow("sleep_rem_min", icon: "moon.fill", title: String(localized: "REM"), \.remMin)
            durationRow("sleep_deep_min", icon: "moon.circle.fill", title: String(localized: "Deep"), \.deepMin)
            durationRow("sleep_light_min", icon: "moon", title: String(localized: "Light"), \.lightMin)
            let eff = GlanceHistory.trend(days: repo.days, through: dayKey, value: day?.efficiency, \.efficiency)
            trendLink("sleep_efficiency", icon: "gauge.with.dots.needle.67percent", title: String(localized: "Efficiency"),
                      value: GlanceFormat.whole(day?.efficiency, unit: "%"), eff,
                      points: GlanceHistory.points(days: repo.days, through: dayKey, \.efficiency),
                      format: { "\(Int($0.rounded()))%" })
        }
        .task {
            restPoints = await repo.exploreSeries(key: "sleep_performance", source: "my-whoop").map { ($0.day, $0.value) }
        }
    }

    private func durationRow(_ key: String, icon: String, title: String,
                             _ column: @escaping (DailyMetric) -> Double?) -> some View {
        let value = day.flatMap(column)
        let trend = GlanceHistory.trend(days: repo.days, through: dayKey, value: value, column)
        return trendLink(key, icon: icon, title: title, value: value.map { GlanceDuration.text(minutes: $0) }, trend,
                         points: GlanceHistory.points(days: repo.days, through: dayKey, column),
                         format: { GlanceDuration.text(minutes: $0) })
    }

    private func trendLink(_ key: String, icon: String, title: String, value: String?,
                           _ trend: (values: [Double], result: UsualRange.Result),
                           points: [(day: String, value: Double)], format: @escaping (Double) -> String) -> some View {
        NavigationLink {
            GlanceTrendDetailPage(series: GlanceTrendSeries(title: title, icon: icon, tint: StrandPalette.restLine,
                                                            points: points, format: format,
                                                            detailsRoute: .metric(key)))
        } label: {
            GlanceTrendRow(icon: icon, title: title, value: value, status: .usual(trend.result),
                           values: trend.values, band: trend.result.band, tint: StrandPalette.restLine)
        }
        .buttonStyle(LiquidPressStyle())
    }
}

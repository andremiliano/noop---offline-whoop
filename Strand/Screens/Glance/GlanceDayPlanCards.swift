import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

// Glance cards that turn the day's numbers into something to act on (#2463): tonight's sleep plan, what
// goes with the wearer's Charge, a first-weeks guide, and timeline rows that open the workout itself.
// Each reads an existing resolver (`TonightPlan` over the Sleep tab's debt ledger, `BehaviorInsights`
// over the Insights inputs, `Baselines`' calibration thresholds); none scores anything new.

// MARK: - Tonight

/// Tonight's sleep need and, with a wake time set, when to be asleep.
struct GlanceTonightCard: View {
    let plan: TonightPlan.Plan

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            HStack(spacing: NoopMetrics.gap) {
                GlanceStatTile(icon: "moon.zzz.fill", label: String(localized: "Sleep need"),
                               value: GlanceDuration.text(minutes: plan.needMin))
                GlanceStatTile(icon: "bed.double.fill", label: String(localized: "Asleep by"),
                               value: plan.asleepBy.map { GlanceFormat.time(Int($0.timeIntervalSince1970)) })
            }
            VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                Text(verbatim: needLine)
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if plan.wake == nil {
                    NavigationLink { SmartAlarmView() } label: {
                        GlanceLinkRow(title: String(localized: "Set your wake time to get a bedtime"), icon: "alarm")
                    }
                    .buttonStyle(.plain)
                } else if let wake = plan.wake {
                    let time = GlanceFormat.time(Int(wake.timeIntervalSince1970))
                    Text(verbatim: plan.wakeSource == .setting
                         ? String(localized: "To wake at \(time), from your wind-down setting.")
                         : String(localized: "To wake at \(time), your usual wake time lately."))
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                    if plan.wakeSource == .usual {
                        NavigationLink { SmartAlarmView() } label: {
                            GlanceLinkRow(title: String(localized: "Set a wake time instead"), icon: "alarm")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(NoopMetrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NoopPanelSurface(cornerRadius: NoopMetrics.cardRadius))
        }
    }

    private var needLine: String {
        let base = GlanceDuration.text(minutes: plan.baseMin)
        guard plan.makeUpMin > 0 else {
            return String(localized: "Your usual need of \(base). No sleep debt to make up.")
        }
        return String(localized: "Your usual \(base), plus \(GlanceDuration.text(minutes: plan.makeUpMin)) to make up recent short nights.")
    }
}

// MARK: - Timeline workout row

/// A workout on a timeline, opening that workout's own page — the same read-only detail the Workouts
/// list opens.
struct GlanceWorkoutTimelineRow: View {
    let workout: WorkoutRow
    let scale: EffortScale

    @State private var showDetail = false
    @EnvironmentObject private var repo: Repository

    var body: some View {
        Button { showDetail = true } label: {
            GlanceTimelineRow(glyph: .workout(workout.sport),
                              badge: workout.strain.map { UnitFormatter.effortDisplay($0, scale: scale) },
                              tint: StrandPalette.effortColor,
                              title: WorkoutSource.displaySport(workout.sport),
                              subtitle: GlanceFormat.time(workout.startTs))
        }
        .buttonStyle(LiquidPressStyle())
        // A sheet with its own stack, as Today's other workout taps use: the detail is read-only, and a
        // sheet keeps it off the tab's path.
        .sheet(isPresented: $showDetail) {
            NavigationStack {
                WorkoutDetailView(row: workout)
                    .environmentObject(repo)
            }
            #if os(iOS)
            .noopSheetPresentation(largeFirst: true)
            #else
            .frame(width: 620, height: 720)
            #endif
        }
    }
}

// MARK: - What goes with your Charge

/// The journal behaviours whose logged days show a clearly different Charge, in plain words. The
/// ranking is `BehaviorInsights.rank` over the same inputs the Insights screen shapes; only effects it
/// marks significant are shown. Opens Insights for the rest.
struct GlanceChargeLinksCard: View {
    @EnvironmentObject private var repo: Repository
    @State private var effects: [BehaviorEffect] = []
    @State private var hasJournal = false

    var body: some View {
        Group {
            if hasJournal {
                NavigationLink(value: TabRoute.insights) {
                    VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                        HStack {
                            Text("What goes with your Charge").font(StrandFont.headline)
                                .foregroundStyle(StrandPalette.textPrimary)
                            Spacer()
                            GlanceChevron()
                        }
                        if effects.isEmpty {
                            Text("Nothing clear yet. Keep answering your journal: after a few weeks of days with and without each habit, NOOP can show which ones go with a higher or lower Charge.")
                                .font(StrandFont.subhead)
                                .foregroundStyle(StrandPalette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            ForEach(effects, id: \.behavior) { row($0) }
                            Text("These go together in your data; that does not prove one causes the other.")
                                .font(StrandFont.caption)
                                .foregroundStyle(StrandPalette.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(NoopMetrics.cardPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(NoopPanelSurface(cornerRadius: NoopMetrics.cardRadius))
                    .contentShape(Rectangle())
                }
                .buttonStyle(LiquidPressStyle())
            }
        }
        .task(id: repo.refreshSeq) { await load() }
    }

    private func row(_ e: BehaviorEffect) -> some View {
        let higher = e.delta > 0
        let size = e.pctChange.map { "\(Int(abs($0).rounded()))%" }
            ?? String(format: "%.0f", locale: AppLanguage.activeLocale, abs(e.delta))
        return HStack(alignment: .firstTextBaseline, spacing: NoopMetrics.space3) {
            Image(systemName: higher ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                .foregroundStyle(higher ? StrandPalette.statusPositive : StrandPalette.statusWarning)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: e.behavior).font(StrandFont.body.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(verbatim: higher
                     ? String(localized: "Charge \(size) higher on days you logged it")
                     : String(localized: "Charge \(size) lower on days you logged it"))
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                Text(verbatim: String(localized: "\(e.nWith) days with it, \(e.nWithout) without"))
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func load() async {
        let entries = await repo.journalEntries()
        hasJournal = !entries.isEmpty
        guard hasJournal else { effects = []; return }
        let (yes, no) = InsightsView.behaviourDays(entries)
        let outcome = InsightsView.outcomeDays(key: "recovery",
                                               series: await repo.series(key: "recovery", source: "my-whoop"),
                                               days: repo.days)
        effects = Array(BehaviorInsights.rank(behaviors: yes, controls: no, outcomeByDay: outcome,
                                              outcome: String(localized: "Charge"))
            .filter(\.significant)
            .prefix(3))
    }
}

// MARK: - First weeks

/// What fills in when, during a wearer's first weeks: Charge after `Baselines.minNightsSeed` nights,
/// their own normal ranges after `Baselines.minNightsTrust`, fuller trends after a month. Hides itself
/// once everything is in, or when dismissed.
struct GlanceGettingStartedCard: View {
    @EnvironmentObject private var repo: Repository
    /// Nights of HRV the Charge baseline has counted, nil once Charge is scoring.
    let chargeCalibratingNights: Int?
    /// Days of history in total.
    let historyDays: Int

    @AppStorage("today.glanceGuideDismissed") private var dismissed = false
    /// The HRV reading's banding, the Health tab's: whether it is judged against the wearer's own normal,
    /// and on how many nights.
    @State private var hrvBanding: VitalBands.Result?
    private let units = GlanceUnitPrefs()

    private var normalNights: Int { hrvBanding?.nights ?? 0 }
    private var chargeReady: Bool { chargeCalibratingNights == nil }
    private var normalReady: Bool { hrvBanding?.basis == .personal }
    private var trendsReady: Bool { historyDays >= 30 }

    var body: some View {
        content.task(id: GlanceVitalInputs.reloadKey(repo, units: units)) {
            hrvBanding = await GlanceVitalInputs.loadReadings(repo, units: units).first { $0.key == "hrv" }?.banding
        }
    }

    @ViewBuilder private var content: some View {
        if !dismissed && !(chargeReady && normalReady && trendsReady) {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                HStack {
                    Text("Your first weeks").font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                    Spacer()
                    Button { dismissed = true } label: {
                        Image(systemName: "xmark").font(StrandFont.subhead).foregroundStyle(StrandPalette.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Hide"))
                }
                step(done: chargeReady, title: String(localized: "Charge"),
                     detail: chargeReady ? String(localized: "Scoring every morning.")
                        : String(localized: "\(chargeCalibratingNights ?? 0) of \(Baselines.minNightsSeed) nights. Wear the strap to sleep."))
                step(done: normalReady, title: String(localized: "Your own normal ranges"),
                     detail: normalReady ? String(localized: "Your vitals are compared with you, not with other people.")
                        : String(localized: "\(min(normalNights, Baselines.minNightsTrust)) of \(Baselines.minNightsTrust) nights. Until then, vitals are compared with the usual adult range."))
                step(done: trendsReady, title: String(localized: "Trends and patterns"),
                     detail: trendsReady ? String(localized: "A month of history to compare against.")
                        : String(localized: "\(historyDays) of 30 days. Weekly patterns and trend analysis get more reliable as days add up."))
            }
            .padding(NoopMetrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NoopPanelSurface(cornerRadius: NoopMetrics.cardRadius))
        }
    }

    private func step(done: Bool, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: NoopMetrics.space3) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(done ? StrandPalette.statusPositive : StrandPalette.textTertiary)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title).font(StrandFont.body.weight(.semibold)).foregroundStyle(StrandPalette.textPrimary)
                Text(verbatim: detail).font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

import SwiftUI
import WhoopStore
import StrandDesign

// MARK: - What the page shows from the wearer's own numbers (no model involved)

/// The day at a glance: today's scores against the wearer's own recent average. Pure and model-free, so the
/// page is useful the moment it opens, with or without a written brief.
struct CoachGlance: Equatable {
    struct Stat: Equatable, Identifiable {
        let id: String
        let label: String
        let value: String
        /// Signed difference from the average of the 14 days before, in the stat's own unit; nil without a baseline.
        let delta: Double?
        let deltaText: String?
        /// Whether a higher number is the good direction (false for resting heart rate).
        let higherIsBetter: Bool
    }

    let day: String
    let charge: Double?
    /// Today's Effort on the wearer's scale, and the band to aim for given today's Charge; nil without Charge.
    let effort: Double?
    let effortTarget: ClosedRange<Double>?
    let effortMax: Double
    let stats: [Stat]
    /// Charge for the last seven days, oldest first; nil where unscored.
    let week: [(day: String, charge: Double?)]

    static func make(from days: [DailyMetric], scale: EffortScale = .hundred) -> CoachGlance? {
        guard let last = days.last else { return nil }
        let prior = Array(days.dropLast().suffix(14))
        func avg(_ f: (DailyMetric) -> Double?) -> Double? {
            let v = prior.compactMap(f)
            return v.count >= 3 ? v.reduce(0, +) / Double(v.count) : nil
        }
        func stat(_ id: String, _ label: String, _ value: Double?, format: (Double) -> String,
                  baseline: Double?, unit: String, higherIsBetter: Bool = true) -> Stat? {
            guard let value else { return nil }
            let delta = baseline.map { value - $0 }
            let text = delta.map { d -> String in
                let r = Int(d.rounded())
                return r == 0 ? "usual" : String(format: "%+d%@", r, unit)
            }
            return Stat(id: id, label: label, value: format(value), delta: delta, deltaText: text,
                        higherIsBetter: higherIsBetter)
        }
        let stats = [
            stat("effort", "Effort", last.strain.map { UnitFormatter.effortValue($0, scale: scale) },
                 format: { String(format: scale == .whoop ? "%.1f" : "%.0f", $0) },
                 baseline: avg { $0.strain.map { UnitFormatter.effortValue($0, scale: scale) } }, unit: ""),
            stat("rest", "Sleep", last.totalSleepMin.map { $0 / 60 },
                 format: { String(format: "%.1fh", $0) },
                 baseline: avg { $0.totalSleepMin.map { $0 / 60 } }, unit: "h"),
            stat("hrv", "HRV", last.avgHrv, format: { "\(Int($0.rounded())) ms" },
                 baseline: avg { $0.avgHrv }, unit: ""),
            stat("rhr", "Resting HR", last.restingHr.map(Double.init), format: { "\(Int($0.rounded())) bpm" },
                 baseline: avg { $0.restingHr.map(Double.init) }, unit: "", higherIsBetter: false),
        ].compactMap { $0 }
        let week = days.suffix(7).map { (day: $0.day, charge: $0.recovery) }
        return CoachGlance(day: last.day, charge: last.recovery,
                           effort: last.strain.map { UnitFormatter.effortValue($0, scale: scale) },
                           effortTarget: EffortTarget.band(charge: last.recovery, scale: scale),
                           effortMax: EffortTarget.axisMax(scale), stats: stats, week: week)
    }

    static func == (a: CoachGlance, b: CoachGlance) -> Bool {
        a.day == b.day && a.charge == b.charge && a.effort == b.effort && a.effortTarget == b.effortTarget
            && a.stats == b.stats
            && a.week.map(\.day) == b.week.map(\.day) && a.week.map(\.charge) == b.week.map(\.charge)
    }
}

// MARK: - The Coach tab: a brief to read, a chat one tap away

/// Coach opens on today's brief laid out as a page; the conversation is behind the bubble.
///
/// The brief is written by the model on the device when it has one (no key, nothing leaves it), or by the
/// provider the wearer chose, falling back to the device model if that provider cannot answer.
struct CoachHomeView: View {
    @EnvironmentObject var coach: AICoachEngine
    @EnvironmentObject var repo: Repository

    @State private var showChat = false

    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    private var glance: CoachGlance? {
        CoachGlance.make(from: repo.days, scale: UnitPrefs.resolveEffortScale(effortScaleRaw))
    }

    var body: some View {
        ScreenScaffold(title: "Coach",
                       subtitle: "Your day at a glance, written from your own numbers.",
                       onRefresh: { await coach.loadPageBrief(force: true) },
                       topBackground: liquidScaffoldSky()) {
            VStack(alignment: .leading, spacing: NoopMetrics.gap) {
                sourceBar
                if let note = coach.fallbackNote { fallbackBanner(note) }
                hero
                if let g = glance, let target = g.effortTarget { targetCard(g, target) }
                if coach.pageBriefLoading && coach.pageBrief == nil { writing }
                if let error = coach.pageBriefError, coach.pageBrief == nil { problem(error) }
                if let brief = coach.pageBrief {
                    if !brief.today.isEmpty || !brief.tonight.isEmpty { todayCard(brief) }
                }
                if let g = glance, g.week.contains(where: { $0.charge != nil }) { weekCard(g) }
                footer
                // Room for the bubble.
                Color.clear.frame(height: 72)
            }
        }
        .overlay(alignment: .bottomTrailing) { askBubble }
        .sheet(isPresented: $showChat) { chatSheet }
        .task {
            // What opening the old chat did: restore the saved conversation, surface a brief the morning
            // notification already wrote, and arm the next scheduled one.
            await coach.loadPersistedMessagesIfNeeded()
            coach.retireStaleConversationIfNeeded()
            if coach.messages.isEmpty, let stored = CoachBriefScheduler.consumeStoredBrief() {
                coach.surfaceScheduledBrief(stored)
            }
            CoachBriefScheduler.activateIfEnabled { await coach.generateBrief() }
            await coach.loadPageBrief()
        }
        // A question handed over by the Today launcher: the chat is where it is sent.
        .task(id: coach.pendingPrompt) {
            if coach.pendingPrompt?.isEmpty == false { showChat = true }
        }
        .onChangeCompat(of: coach.provider) { _ in
            Task { await coach.loadPageBrief() }
        }
    }

    // MARK: Source + provider

    private var sourceBar: some View {
        HStack(spacing: NoopMetrics.space2) {
            Image(systemName: coach.pageBriefSource == "On this device" ? "iphone" : "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(StrandPalette.accent)
            Text(verbatim: sourceText)
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
            if let date = coach.pageBriefDate {
                Text(date, style: .time)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
            Spacer()
            if coach.pageBriefLoading { ProgressView().controlSize(.small) }
            Button {
                Task { await coach.loadPageBrief(force: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            .buttonStyle(.plain)
            .disabled(coach.pageBriefLoading)
            .accessibilityLabel(String(localized: "Write a new brief"))
            providerMenu
        }
    }

    private var sourceText: String {
        guard let source = coach.pageBriefSource else { return String(localized: "Coach") }
        return source == "On this device" ? String(localized: "Written on this device")
                                          : String(localized: "Written by \(source)")
    }

    /// Choosing what writes the brief: the model on this device, or a provider with the wearer's own key.
    private var providerMenu: some View {
        Menu {
            Section(String(localized: "Written by")) {
                ForEach(AIProvider.allCases) { p in
                    Button {
                        coach.provider = p
                        // A provider with no key yet needs one: the chat's setup card is where it goes.
                        if p != .onDevice, !coach.isConfigured { showChat = true }
                    } label: {
                        if coach.provider == p {
                            Label(p.displayName, systemImage: "checkmark")
                        } else {
                            Text(p.displayName)
                        }
                    }
                    .disabled(p == .onDevice && !OnDeviceAI.isAvailable)
                }
            }
            Toggle(String(localized: "Use this device if the provider fails"), isOn: $coach.fallbackToDevice)
            if case .unavailable(let why) = OnDeviceAI.status {
                Text(verbatim: why)
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(StrandPalette.textSecondary)
        }
        .accessibilityLabel(String(localized: "Choose what writes the brief"))
    }

    // MARK: Hero

    private var hero: some View {
        StrandCard(padding: NoopMetrics.cardPadding) {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                HStack(alignment: .center, spacing: NoopMetrics.space3) {
                    ChargeRing(value: glance?.charge)
                        .frame(width: 84, height: 84)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: coach.pageBrief?.headline.coachPlain.nonEmpty ?? Self.dayTitle(glance?.charge))
                            .font(StrandFont.headline)
                            .foregroundStyle(StrandPalette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let r = coach.pageBrief?.readiness, !r.isEmpty {
                            Text(r.coachInline)
                                .font(StrandFont.subhead)
                                .foregroundStyle(StrandPalette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if let stats = glance?.stats.filter({ $0.id != "effort" }), !stats.isEmpty {
                    Divider().overlay(StrandPalette.hairline)
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(stats) { StatColumn(stat: $0) }
                    }
                    Text("Compared with your usual over the last 14 days")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
            }
        }
    }

    /// A plain headline for the page before (or without) a written one.
    static func dayTitle(_ charge: Double?) -> String {
        guard let c = charge else { return String(localized: "Waiting for today's numbers") }
        switch c {
        case 67...: return String(localized: "Green light today")
        case 34..<67: return String(localized: "Steady day")
        default: return String(localized: "Recovery day")
        }
    }

    // MARK: Sections

    /// How hard to go today, from today's Charge: the band to aim for and where the day stands in it.
    private func targetCard(_ g: CoachGlance, _ band: ClosedRange<Double>) -> some View {
        let digits = UnitPrefs.resolveEffortScale(effortScaleRaw) == .whoop ? 1 : 0
        func n(_ v: Double) -> String { String(format: "%.\(digits)f", v) }
        let now = g.effort ?? 0
        let state: String = {
            guard g.effort != nil else { return String(localized: "Not started yet") }
            if now < band.lowerBound {
                let togo = n(band.lowerBound - now)
                return String(localized: "\(togo) to go to reach the target")
            }
            if now > band.upperBound { return String(localized: "Past the target, ease off") }
            return String(localized: "In the target range")
        }()
        return VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            Text("Effort target").strandOverline()
            StrandCard(padding: NoopMetrics.cardPadding) {
                VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(verbatim: "\(n(band.lowerBound)) – \(n(band.upperBound))")
                            .font(StrandFont.number(24))
                            .foregroundStyle(StrandPalette.textPrimary)
                        Spacer()
                        Text(verbatim: state)
                            .font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                    GeometryReader { geo in
                        let w = geo.size.width
                        let mx = max(g.effortMax, 1)
                        ZStack(alignment: .leading) {
                            Capsule().fill(StrandPalette.surfaceInset)
                            Capsule().fill(StrandPalette.effortColor.opacity(0.28))
                                .frame(width: w * (band.upperBound - band.lowerBound) / mx)
                                .offset(x: w * band.lowerBound / mx)
                            Capsule().fill(StrandPalette.effortColor)
                                .frame(width: max(8, w * min(now, mx) / mx))
                        }
                    }
                    .frame(height: 10)
                    .accessibilityHidden(true)
                }
            }
        }
    }

    /// One card, not four: what to do today and tonight, a line each with an icon to scan by.
    private func todayCard(_ brief: CoachBriefContent) -> some View {
        var rows: [(icon: String, title: String, detail: String)] = brief.today.enumerated().map {
            (Self.icon(for: $0.element.title, index: $0.offset), $0.element.title.coachPlain, $0.element.detail)
        }
        if !brief.tonight.isEmpty { rows.append(("moon.stars.fill", String(localized: "Tonight"), brief.tonight)) }
        return VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            Text("Today").strandOverline()
            StrandCard(padding: NoopMetrics.cardPadding) {
                VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                        if i > 0 { Divider().overlay(StrandPalette.hairline) }
                        HStack(alignment: .top, spacing: NoopMetrics.space3) {
                            Image(systemName: r.icon)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(r.icon == "moon.stars.fill" ? StrandPalette.restLine : StrandPalette.accent)
                                .frame(width: 24)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(verbatim: r.title)
                                    .font(StrandFont.subhead.weight(.semibold))
                                    .foregroundStyle(StrandPalette.textPrimary)
                                Text(r.detail.coachInline)
                                    .font(StrandFont.subhead)
                                    .foregroundStyle(StrandPalette.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    static func icon(for title: String, index: Int) -> String {
        let t = title.lowercased()
        if t.contains("train") || t.contains("workout") || t.contains("lift") || t.contains("run") { return "figure.run" }
        if t.contains("sleep") || t.contains("bed") || t.contains("rest") { return "bed.double.fill" }
        if t.contains("fuel") || t.contains("eat") || t.contains("food") || t.contains("hydrat") { return "fork.knife" }
        if t.contains("recover") || t.contains("easy") || t.contains("mobility") { return "leaf.fill" }
        return ["bolt.fill", "heart.fill", "star.fill"][index % 3]
    }

    private func weekCard(_ g: CoachGlance) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            Text("Charge, last 7 days").strandOverline()
            StrandCard(padding: NoopMetrics.cardPadding) {
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(Array(g.week.enumerated()), id: \.offset) { _, d in
                        VStack(spacing: 6) {
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 5).fill(StrandPalette.surfaceInset)
                                if let c = d.charge {
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(StrandPalette.chargeColor.opacity(0.35 + 0.65 * min(max(c, 0), 100) / 100))
                                        .frame(height: max(5, 40 * min(max(c, 0), 100) / 100))
                                }
                            }
                            .frame(height: 40)
                            Text(verbatim: c(d.charge))
                                .font(StrandFont.caption)
                                .foregroundStyle(StrandPalette.textSecondary)
                            Text(verbatim: Self.weekday(d.day))
                                .font(StrandFont.caption)
                                .foregroundStyle(StrandPalette.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private func c(_ v: Double?) -> String { v.map { "\(Int($0.rounded()))" } ?? "–" }

    private static func weekday(_ day: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        guard let d = f.date(from: day) else { return "" }
        let out = DateFormatter()
        out.locale = AppLanguage.activeLocale
        out.setLocalizedDateFormatFromTemplate("EEEEE")
        return out.string(from: d)
    }

    // MARK: States

    private var writing: some View {
        StrandCard(padding: NoopMetrics.cardPadding) {
            HStack(spacing: NoopMetrics.space3) {
                ProgressView()
                Text("Writing today's brief…")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
        }
    }

    private func problem(_ message: String) -> some View {
        StrandCard(padding: NoopMetrics.cardPadding) {
            VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                Text(verbatim: message)
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try again") { Task { await coach.loadPageBrief(force: true) } }
                    .buttonStyle(.bordered)
            }
        }
    }

    private func fallbackBanner(_ note: String) -> some View {
        Label {
            Text(verbatim: note).font(StrandFont.caption)
        } icon: {
            Image(systemName: "iphone")
        }
        .foregroundStyle(StrandPalette.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var footer: some View {
        Text("Coaching from your own data, not medical advice. Ask a follow-up with the bubble.")
            .font(StrandFont.caption)
            .foregroundStyle(StrandPalette.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Chat bubble + sheet

    private var askBubble: some View {
        Button {
            showChat = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "bubble.left.and.text.bubble.right.fill")
                Text("Ask Coach").font(StrandFont.subhead.weight(.semibold))
            }
            .foregroundStyle(StrandPalette.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Capsule().fill(StrandPalette.accent.opacity(0.9)))
            .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .padding(.trailing, NoopMetrics.space4)
        .padding(.bottom, NoopMetrics.space4)
        .accessibilityLabel(String(localized: "Ask the coach a question"))
    }

    private var chatSheet: some View {
        Group {
            if coach.isConfigured {
                CoachChatView(onDone: { showChat = false })
            } else {
                // Not set up: the original screen carries the provider and key setup.
                NavigationStack {
                    CoachView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showChat = false }
                            }
                        }
                }
            }
        }
        .environmentObject(coach)
        .environmentObject(repo)
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 680)
        #endif
    }
}

// MARK: - Pieces

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

/// The day's Charge as a ring, the number in the middle; a dash while there is none.
private struct ChargeRing: View {
    let value: Double?

    var body: some View {
        ZStack {
            Circle().stroke(StrandPalette.surfaceInset, lineWidth: 9)
            if let value {
                Circle()
                    .trim(from: 0, to: min(max(value, 0), 100) / 100)
                    .stroke(StrandPalette.chargeColor, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: 0) {
                Text(verbatim: value.map { "\(Int($0.rounded()))" } ?? "–")
                    .font(StrandFont.number(26))
                    .foregroundStyle(StrandPalette.textPrimary)
                Text("Charge").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Charge"))
        .accessibilityValue(Text(verbatim: value.map { "\(Int($0.rounded())) percent" } ?? "none"))
    }
}

private struct StatColumn: View {
    let stat: CoachGlance.Stat

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: stat.value)
                .font(StrandFont.number(17))
                .foregroundStyle(StrandPalette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(verbatim: stat.label)
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
            if let t = stat.deltaText {
                Text(verbatim: Self.arrow(stat.delta) + t.trimmingCharacters(in: CharacterSet(charactersIn: "+-−")))
                    .font(StrandFont.caption.weight(.medium))
                    .foregroundStyle(color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// ▲ above usual, ▼ below, nothing when it is the usual.
    private static func arrow(_ d: Double?) -> String {
        guard let d, abs(d) >= 0.5 else { return "" }
        return d > 0 ? "▲ " : "▼ "
    }

    private var color: Color {
        guard let d = stat.delta, abs(d) >= 0.5 else { return StrandPalette.textTertiary }
        return (d > 0) == stat.higherIsBetter ? StrandPalette.statusPositive : StrandPalette.metricAmber
    }
}

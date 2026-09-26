import SwiftUI
import StrandDesign
import StrandAnalytics

// Glance's Body Age (#2463): a small row at the end of Today, opening a page that says what the number
// is, what is shaping it and how it is worked out. The number is the stored weekly `body_age` the Health
// tab shows; the breakdown is `VitalityBreakdown`, the Health tab's own. Nothing is recomputed here.

/// The stored Body Age and Vitality, loaded once per data change.
private struct BodyAgeValues {
    var bodyAge: Double?
    var vitality: Double?

    @MainActor
    static func load(_ repo: Repository) async -> BodyAgeValues {
        BodyAgeValues(bodyAge: (await repo.exploreSeries(key: "body_age", source: "my-whoop")).last?.value,
                      vitality: (await repo.exploreSeries(key: "vitality", source: "my-whoop")).last?.value)
    }
}

/// One line at the end of Today: the estimated Body Age, opening its page.
struct GlanceBodyAgeRow: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @State private var values = BodyAgeValues()

    var body: some View {
        Group {
            if let ba = values.bodyAge {
                NavigationLink { GlanceBodyAgePage() } label: {
                    HStack(spacing: NoopMetrics.space3) {
                        Image(systemName: "hourglass")
                            .foregroundStyle(StrandPalette.chargeColor)
                        Text("Body Age").font(StrandFont.body).foregroundStyle(StrandPalette.textPrimary)
                        Text("estimate").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                        Spacer()
                        Text(verbatim: String(format: "%.1f", locale: AppLanguage.activeLocale, ba))
                            .font(StrandFont.number(17))
                            .foregroundStyle(StrandPalette.textPrimary)
                        let delta = Double(profile.age) - ba
                        Text(verbatim: BodyAgeText.delta(yrs: Int(abs(delta).rounded()), younger: delta >= 0))
                            .font(StrandFont.caption)
                            .foregroundStyle(delta >= 0 ? StrandPalette.statusPositive : StrandPalette.statusWarning)
                        Image(systemName: "chevron.right").font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textTertiary)
                    }
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .padding(.horizontal, NoopMetrics.cardPadding)
                    .padding(.vertical, NoopMetrics.space3)
                    .background(NoopPanelSurface(cornerRadius: 18))
                    .contentShape(Rectangle())
                }
                .buttonStyle(LiquidPressStyle())
                .accessibilityElement(children: .combine)
            }
        }
        .task(id: repo.refreshSeq) { values = await BodyAgeValues.load(repo) }
    }
}

/// What Body Age is, what is shaping it, and how it is worked out.
struct GlanceBodyAgePage: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @State private var values = BodyAgeValues()

    var body: some View {
        GlanceScorePage(title: String(localized: "Body Age"), tint: StrandPalette.chargeColor, guide: nil) {
            hero
            factors
            howCard
            NavigationLink { TabRoute.health.destination } label: {
                GlanceLinkRow(title: String(localized: "See it in Health"), icon: "heart.text.square")
            }
            .buttonStyle(.plain)
        }
        .task(id: repo.refreshSeq) { values = await BodyAgeValues.load(repo) }
    }

    // MARK: Hero

    @ViewBuilder private var hero: some View {
        VStack(spacing: NoopMetrics.space2) {
            if let ba = values.bodyAge {
                let delta = Double(profile.age) - ba
                Text(verbatim: String(format: "%.1f", locale: AppLanguage.activeLocale, ba))
                    .font(StrandFont.number(56))
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(verbatim: BodyAgeText.delta(yrs: Int(abs(delta).rounded()), younger: delta >= 0))
                    .font(StrandFont.headline)
                    .foregroundStyle(delta >= 0 ? StrandPalette.statusPositive : StrandPalette.statusWarning)
                Text(verbatim: String(localized: "Your age: \(profile.age) · give or take \(Int(VitalityEngine.bandYears)) years"))
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                if let v = values.vitality {
                    Text(verbatim: String(localized: "Vitality \(Int(v.rounded())) of 100"))
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
            } else {
                Text("A few more days and we can show your Vitality.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, NoopMetrics.space6)
    }

    // MARK: What's shaping it

    private struct Factor: Identifiable {
        let id: String
        let icon: String
        let title: String
        let value: String?
        let lnHazard: Double
    }

    private var factorRows: [Factor] {
        let inputs = VitalityBreakdown.inputs(days: repo.days, age: profile.age)
        return VitalityEngine.contributions(inputs).map { c in
            switch c.key {
            case "rhr":
                return Factor(id: c.key, icon: "heart.fill", title: String(localized: "Resting heart rate"),
                              value: inputs.restingHR.map { "\(Int($0.rounded())) bpm" }, lnHazard: c.lnHazard)
            case "sleep":
                return Factor(id: c.key, icon: "bed.double.fill", title: String(localized: "Sleep duration"),
                              value: inputs.sleepHours.map { GlanceDuration.text(minutes: $0 * 60) }, lnHazard: c.lnHazard)
            case "consistency":
                return Factor(id: c.key, icon: "clock.fill", title: String(localized: "Sleep regularity"),
                              value: inputs.sleepConsistency.map { "\(Int(($0 * 100).rounded()))%" }, lnHazard: c.lnHazard)
            case "hrv":
                return Factor(id: c.key, icon: "waveform.path.ecg", title: String(localized: "Heart-rate variability"),
                              value: inputs.rmssd.map { "\(Int($0.rounded())) ms" }, lnHazard: c.lnHazard)
            case "steps":
                return Factor(id: c.key, icon: "figure.walk", title: String(localized: "Daily steps"),
                              value: inputs.steps.map { Self.stepsText($0) }, lnHazard: c.lnHazard)
            default:
                return Factor(id: c.key, icon: "circle", title: String(localized: "Cardio fitness"),
                              value: nil, lnHazard: c.lnHazard)
            }
        }
        .sorted { $0.lnHazard < $1.lnHazard }
    }

    @ViewBuilder private var factors: some View {
        let rows = factorRows
        if !rows.isEmpty {
            let largest = max(rows.map { abs($0.lnHazard) }.max() ?? 0, 1e-6)
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                Text("What's shaping it").font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                ForEach(rows) { f in
                    factorRow(f, share: abs(f.lnHazard) / largest)
                }
                Text("From your last 7 days. Bars compare the factors with each other.")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(NoopMetrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NoopPanelSurface(cornerRadius: NoopMetrics.cardRadius))
        }
    }

    private func factorRow(_ f: Factor, share: Double) -> some View {
        // Negative log-hazard is protective (it takes years off); positive adds years.
        let helping = f.lnHazard < -0.005, holding = f.lnHazard > 0.005
        let tint = helping ? StrandPalette.statusPositive : (holding ? StrandPalette.statusWarning : StrandPalette.textTertiary)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: NoopMetrics.space2) {
                Image(systemName: f.icon).foregroundStyle(StrandPalette.textSecondary).frame(width: 20)
                Text(verbatim: f.title).font(StrandFont.body).foregroundStyle(StrandPalette.textPrimary)
                Spacer()
                if let v = f.value {
                    Text(verbatim: v).font(StrandFont.bodyNumber).foregroundStyle(StrandPalette.textSecondary)
                }
            }
            HStack(spacing: NoopMetrics.space2) {
                GeometryReader { geo in
                    Capsule().fill(StrandPalette.surfaceInset)
                        .overlay(alignment: .leading) {
                            Capsule().fill(tint).frame(width: max(4, geo.size.width * CGFloat(share)))
                        }
                }
                .frame(height: 6)
                Text(verbatim: helping ? String(localized: "Helping")
                     : (holding ? String(localized: "Adding years") : String(localized: "Neutral")))
                    .font(StrandFont.caption.weight(.medium))
                    .foregroundStyle(tint)
                    .frame(width: 96, alignment: .trailing)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: How it's worked out

    private var howCard: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space3) {
            Text("How it's worked out").font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
            paragraph(String(localized: "Body Age looks at five things your strap measures over the last 7 days: resting heart rate, sleep duration, how regular your sleep is, heart-rate variability compared with others your age, and daily steps."))
            paragraph(String(localized: "Each is compared with a typical person, using large published studies (such as UK Biobank) that link it to long-term health. Better than typical takes years off; worse adds years."))
            paragraph(String(localized: "The effects are combined, trimmed so related measures are not counted twice, and turned into years. It updates once a week and needs at least 3 of the 5 measures."))
            paragraph(String(localized: "A wellness estimate from your habits, not a clinical biological age."))
        }
        .padding(NoopMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NoopPanelSurface(cornerRadius: NoopMetrics.cardRadius))
    }

    private func paragraph(_ text: String) -> some View {
        Text(verbatim: text)
            .font(StrandFont.subhead)
            .foregroundStyle(StrandPalette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private static func stepsText(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = AppLanguage.activeLocale
        return f.string(from: NSNumber(value: Int(v.rounded()))) ?? "\(Int(v.rounded()))"
    }
}

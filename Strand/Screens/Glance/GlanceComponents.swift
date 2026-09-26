import SwiftUI
import StrandDesign
import StrandAnalytics

// Glance building blocks (#2463): the trend row, stat tile, timeline row, zone row and score hero the
// Glance Today and its score pages are made of. Presentation only — every value, band and status arrives
// resolved by the caller, so a block cannot state a fact its source does not.

// MARK: - Status

/// A trend row's one-line verdict: its words, symbol and colour, resolved together so they cannot
/// disagree.
struct GlanceStatus: Equatable {
    enum Tone: Equatable { case good, info, warning, muted }

    let text: String
    let icon: String
    let tone: Tone

    var color: Color {
        switch tone {
        case .good:    return StrandPalette.statusPositive
        case .info:    return StrandPalette.accent
        case .warning: return StrandPalette.statusWarning
        case .muted:   return StrandPalette.textTertiary
        }
    }

    /// A score or duration against its own recent range. Direction is stated, not judged: a higher
    /// Effort or a shorter night is not good or bad on its own.
    static func usual(_ result: UsualRange.Result) -> GlanceStatus {
        switch result.status {
        case .usual:
            return GlanceStatus(text: String(localized: "Normal for you"), icon: "checkmark.circle.fill", tone: .good)
        case .above:
            return GlanceStatus(text: String(localized: "Higher than usual"), icon: "arrow.up.circle.fill", tone: .info)
        case .below:
            return GlanceStatus(text: String(localized: "Lower than usual"), icon: "arrow.down.circle.fill", tone: .info)
        case .notEnoughHistory:
            return GlanceStatus(text: String(localized: "Building your range"), icon: "clock.fill", tone: .muted)
        case .noData:
            return GlanceStatus(text: String(localized: "No data"), icon: "xmark.circle.fill", tone: .muted)
        }
    }

    /// A vital against the range its banding used, saying WHICH range and which way: the wearer's own
    /// normal once NOOP has learned it, the usual adult range until then.
    static func vital(_ reading: BodyVitalReading) -> GlanceStatus {
        let personal = reading.banding.basis == .personal
        guard reading.key != "spo2raw", let v = reading.value else {
            return GlanceStatus(text: String(localized: "No data"), icon: "xmark.circle.fill", tone: .muted)
        }
        switch reading.banding.band {
        case .noData:
            return GlanceStatus(text: String(localized: "No data"), icon: "xmark.circle.fill", tone: .muted)
        case .inRange:
            return GlanceStatus(text: personal ? String(localized: "Normal for you") : String(localized: "Usual adult range"),
                                icon: "checkmark.circle.fill", tone: .good)
        case .outOfRange:
            let higher = reading.normalRange.map { v > $0.upperBound } ?? false
            let text: String
            switch (personal, higher) {
            case (true, true):   text = String(localized: "Higher than your normal")
            case (true, false):  text = String(localized: "Lower than your normal")
            case (false, true):  text = String(localized: "Above the usual adult range")
            case (false, false): text = String(localized: "Below the usual adult range")
            }
            return GlanceStatus(text: text, icon: higher ? "arrow.up.circle.fill" : "arrow.down.circle.fill", tone: .warning)
        }
    }
}

// MARK: - Sparkline over a band

/// A small trend line over the wearer's usual band, ending on a marked "now" point.
struct GlanceSparkBand: View {
    let values: [Double]
    let band: ClosedRange<Double>?
    let tint: Color

    var body: some View {
        Canvas { ctx, size in
            guard values.count >= 2 else { return }
            var lo = values.min() ?? 0, hi = values.max() ?? 1
            if let band { lo = min(lo, band.lowerBound); hi = max(hi, band.upperBound) }
            let span = max(hi - lo, 1e-6)
            let inset: CGFloat = 5
            let h = size.height - inset * 2
            func y(_ v: Double) -> CGFloat { inset + h - CGFloat((v - lo) / span) * h }
            let step = (size.width - inset * 2) / CGFloat(values.count - 1)
            if let band {
                let rect = CGRect(x: 0, y: y(band.upperBound), width: size.width,
                                  height: max(2, y(band.lowerBound) - y(band.upperBound)))
                ctx.fill(Path(roundedRect: rect, cornerRadius: 4), with: .color(tint.opacity(0.18)))
            }
            var line = Path()
            for (i, v) in values.enumerated() {
                let p = CGPoint(x: inset + CGFloat(i) * step, y: y(v))
                if i == 0 { line.move(to: p) } else { line.addLine(to: p) }
            }
            ctx.stroke(line, with: .color(tint), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            let end = CGPoint(x: inset + CGFloat(values.count - 1) * step, y: y(values[values.count - 1]))
            ctx.fill(Path(ellipseIn: CGRect(x: end.x - 5, y: end.y - 5, width: 10, height: 10)),
                     with: .color(StrandPalette.surfaceBase))
            ctx.stroke(Path(ellipseIn: CGRect(x: end.x - 4, y: end.y - 4, width: 8, height: 8)),
                       with: .color(tint), lineWidth: 2.5)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Trend row

/// One metric in a Trends list: its name, today's value, where it sits against the wearer's own range,
/// and a sparkline of the recent days over that range.
struct GlanceTrendRow: View {
    let icon: String
    let title: String
    let value: String?
    let status: GlanceStatus
    let values: [Double]
    let band: ClosedRange<Double>?
    let tint: Color

    var body: some View {
        HStack(alignment: .center, spacing: NoopMetrics.space3) {
            VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                Label {
                    Text(verbatim: title).font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                } icon: {
                    Image(systemName: icon).foregroundStyle(StrandPalette.textTertiary)
                }
                .lineLimit(1)
                Text(verbatim: value ?? String(localized: "No data"))
                    .font(StrandFont.number(value == nil ? 22 : 28))
                    .foregroundStyle(value == nil ? StrandPalette.textTertiary : StrandPalette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.6)
                GlanceStatusLine(status: status)
            }
            Spacer(minLength: NoopMetrics.space2)
            GlanceSparkBand(values: values, band: band, tint: tint)
                .frame(width: 120, height: 56)
        }
        .overlay(alignment: .topTrailing) { GlanceChevron() }
        .padding(NoopMetrics.cardPadding)
        .background(NoopPanelSurface(cornerRadius: NoopMetrics.cardRadius))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// The status symbol and words under a value.
struct GlanceStatusLine: View {
    let status: GlanceStatus

    var body: some View {
        Label {
            Text(verbatim: status.text).font(StrandFont.subhead.weight(.medium))
        } icon: {
            Image(systemName: status.icon)
        }
        .foregroundStyle(status.color)
        .lineLimit(1).minimumScaleFactor(0.8)
    }
}

/// The small "opens more" arrow in a card's corner.
struct GlanceChevron: View {
    var body: some View {
        Image(systemName: "arrow.right")
            .font(StrandFont.subhead)
            .foregroundStyle(StrandPalette.textTertiary)
            .accessibilityHidden(true)
    }
}

// MARK: - Stat tile

/// A labelled figure with a header strip, as used in pairs under a score's ring.
struct GlanceStatTile: View {
    let icon: String
    let label: String
    let value: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label {
                Text(verbatim: label).font(StrandFont.subhead)
            } icon: {
                Image(systemName: icon)
            }
            .foregroundStyle(StrandPalette.textSecondary)
            .lineLimit(1).minimumScaleFactor(0.8)
            .padding(.horizontal, NoopMetrics.space4)
            .padding(.vertical, NoopMetrics.space3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(StrandPalette.surfaceInset.opacity(0.5))
            Text(verbatim: value ?? "—")
                .font(StrandFont.number(30))
                .foregroundStyle(value == nil ? StrandPalette.textTertiary : StrandPalette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
                .padding(NoopMetrics.space4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(NoopPanelSurface(cornerRadius: NoopMetrics.cardRadius))
        .clipShape(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Synthesis card

/// The one-sentence read of the day, under an overline.
struct GlanceSynthesisCard: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            Text("Synthesis").strandOverline()
            Text(verbatim: text)
                .font(StrandFont.body)
                .foregroundStyle(StrandPalette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(NoopMetrics.cardPadding)
        .background(NoopPanelSurface(cornerRadius: NoopMetrics.cardRadius))
    }
}

// MARK: - Timeline row

/// One entry on the day's timeline: a workout or a night, with its score as a badge.
struct GlanceTimelineRow: View {
    enum Glyph { case workout(String), sleep }

    let glyph: Glyph
    let badge: String?
    let tint: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: NoopMetrics.space4) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(StrandPalette.surfaceInset)
                    .frame(width: 52, height: 52)
                    .overlay {
                        switch glyph {
                        case .workout(let sport): WorkoutTypeIcon(workoutType: sport, size: 24, color: tint)
                        case .sleep: Image(systemName: "moon.stars.fill").font(.system(size: 22)).foregroundStyle(tint)
                        }
                    }
                if let badge {
                    Text(verbatim: badge)
                        .font(StrandFont.captionNumber.weight(.bold))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(StrandPalette.surfaceBase))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(tint, lineWidth: 1.5))
                        .offset(x: 8, y: 6)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: title).font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                Text(verbatim: subtitle).font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
            }
            .lineLimit(1)
            Spacer(minLength: 0)
            GlanceChevron()
        }
        .padding(NoopMetrics.cardPadding)
        .background(NoopPanelSurface(cornerRadius: NoopMetrics.cardRadius))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Heart-rate zone row

/// Time in one heart-rate zone, its bar sized against the longest zone, and the zone's bpm range.
struct GlanceZoneRow: View {
    let zone: Int
    let minutes: Double
    /// Minutes in the longest zone, so the bars share one scale.
    let longest: Double
    let bpmRange: String?

    var body: some View {
        HStack(spacing: NoopMetrics.space3) {
            Text(verbatim: "\(zone)")
                .font(StrandFont.number(17))
                .foregroundStyle(StrandPalette.textTertiary)
                .frame(width: 16)
            GeometryReader { geo in
                Capsule()
                    .fill(StrandPalette.hrZoneColor(zone))
                    .frame(width: max(4, geo.size.width * CGFloat(longest > 0 ? minutes / longest : 0)), height: 8)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 80)
            Text(verbatim: GlanceFormat.clock(minutes: minutes))
                .font(StrandFont.number(17))
                .foregroundStyle(StrandPalette.textPrimary)
            Spacer(minLength: 0)
            if let bpmRange {
                Text(verbatim: bpmRange).font(StrandFont.subhead).foregroundStyle(StrandPalette.textTertiary)
            }
        }
        .padding(.horizontal, NoopMetrics.space4)
        .padding(.vertical, NoopMetrics.space3)
        .background(NoopPanelSurface(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Section title

/// A Glance section heading.
struct GlanceSectionTitle: View {
    let title: String

    var body: some View {
        Text(verbatim: title)
            .font(StrandFont.title2)
            .foregroundStyle(StrandPalette.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, NoopMetrics.space3)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Score hero

/// The top of a score page: the date and the ring, with the day's target arc around it when there is
/// one. The score's name is the page's title, so it is not repeated here.
struct GlanceScoreHero: View {
    let subtitle: String
    let score: Double?
    let tint: Color
    var maxValue: Double = 100
    var decimals: Int = 0
    var caption: String? = nil
    /// A target band on the ring's axis, drawn as an arc around it.
    var target: ClosedRange<Double>? = nil

    var body: some View {
        VStack(spacing: NoopMetrics.space2) {
            Text(verbatim: subtitle)
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
            LiquidScoreGauge(score: score, tint: tint, diameter: 176, animated: true,
                             maxValue: maxValue, decimals: decimals, tapPassesThrough: true)
                .overlay {
                    if let target {
                        LiquidTargetZone(from: target.lowerBound / maxValue, to: target.upperBound / maxValue,
                                         tint: StrandPalette.textPrimary.opacity(0.5))
                    }
                }
                .padding(.vertical, NoopMetrics.space5)
            if let caption {
                Text(verbatim: caption)
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, NoopMetrics.space4)
        .padding(.bottom, NoopMetrics.space2)
    }
}

/// The score page backdrop: the day's sky with a glow in the score's colour, fading to the canvas.
struct GlanceScoreBackdrop: View {
    let tint: Color

    var body: some View {
        ZStack(alignment: .top) {
            StrandPalette.surfaceBase
            LiquidSkyStatic(hour: nil)
                .frame(height: 440)
            RadialGradient(colors: [tint.opacity(0.35), .clear],
                           center: UnitPoint(x: 0.5, y: 0.3), startRadius: 0, endRadius: 280)
                .frame(height: 440)
            LinearGradient(colors: [.clear, StrandPalette.surfaceBase], startPoint: .center, endPoint: .bottom)
                .frame(height: 440)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Formatting

enum GlanceFormat {
    /// Minutes as a zone clock, "00:19:27".
    static func clock(minutes: Double) -> String {
        let s = Int((max(0, minutes) * 60).rounded())
        return String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }

    /// A score exactly as its ring prints it (`CountUpNumber`): a whole number rounded half away from
    /// zero, or `decimals` places. A row and the ring above it must never print one value two ways — a
    /// bare "%.0f" rounds 82.5 to 82 while the ring shows 83.
    static func score(_ v: Double, decimals: Int) -> String {
        decimals > 0 ? String(format: "%.\(decimals)f", v) : "\(Int(v.rounded()))"
    }

    /// A whole-number figure with an optional unit, "52 bpm".
    static func whole(_ v: Double?, unit: String = "") -> String? {
        guard let v else { return nil }
        let n = String(Int(v.rounded()))
        return unit.isEmpty ? n : "\(n) \(unit)"
    }

    /// Formatters are costly to build and these run in row bodies, so each is built once and only its
    /// locale refreshed, since the app's language can change while running.
    private static let dayFormatter = DateFormatter()
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    /// "Today, 25 September" / "Wednesday, 24 September", in the app's language.
    static func dayTitle(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return String(localized: "Today, \(DateFormatter.localizedDayMonth(date))")
        }
        dayFormatter.locale = AppLanguage.activeLocale
        dayFormatter.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return dayFormatter.string(from: date)
    }

    /// A local clock time, "23:14".
    static func time(_ ts: Int) -> String {
        timeFormatter.locale = AppLanguage.activeLocale
        return timeFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
    }
}

extension DateFormatter {
    private static let dayMonth = DateFormatter()

    /// "25 September", in the app's language.
    static func localizedDayMonth(_ date: Date) -> String {
        dayMonth.locale = AppLanguage.activeLocale
        dayMonth.setLocalizedDateFormatFromTemplate("dMMMM")
        return dayMonth.string(from: date)
    }
}

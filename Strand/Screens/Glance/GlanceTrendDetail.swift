import SwiftUI
import Charts
import StrandDesign

// Glance's trend detail (#2463): what a trend row or a vital opens. An interactive chart of the wearer's
// own series over a chosen window, with its normal range and average; the average by weekday; and how
// the last 3, 7, 14 and 30 days compare with the days before them (`TrendAnalysis`). The full technical
// metric page stays one tap on.

/// One metric's day series and how to show it.
struct GlanceTrendSeries {
    let title: String
    let icon: String
    let tint: Color
    /// Oldest → newest; one value per day.
    let points: [(day: String, value: Double)]
    /// A value with its unit, e.g. "7h 48m", "52 bpm".
    let format: (Double) -> String
    /// The range to shade: a vital's normal range, or nil to shade the middle 80% of the shown days.
    var band: ClosedRange<Double>? = nil
    /// The full technical page, or nil.
    var detailsRoute: TabRoute? = nil
}

/// A trend row's destination: the series' analysis under its own title.
///
/// The series is taken as an autoclosure: a `NavigationLink` builds its destination with the row, so an
/// eagerly built series would re-slice the whole history for every row on every render of the page.
struct GlanceTrendDetailPage: View {
    private let makeSeries: () -> GlanceTrendSeries

    init(series: @autoclosure @escaping () -> GlanceTrendSeries) {
        makeSeries = series
    }

    var body: some View {
        let series = makeSeries()
        GlanceScorePage(title: series.title, tint: series.tint, guide: nil) {
            GlanceTrendSections(series: series)
                .padding(.top, NoopMetrics.space4)
        }
    }
}

/// The chart, the weekday view, the trend analysis and the link to the full page, for embedding.
struct GlanceTrendSections: View {
    let series: GlanceTrendSeries

    enum Window: Int, CaseIterable, Identifiable {
        case month = 30, quarter = 90, half = 180, year = 365
        var id: Int { rawValue }
        var label: String {
            switch self {
            case .month: return String(localized: "30D")
            case .quarter: return String(localized: "3M")
            case .half: return String(localized: "6M")
            case .year: return String(localized: "1Y")
            }
        }
    }

    @State private var window: Window = .month
    @State private var selectedX: CGFloat?

    private struct Row: Identifiable {
        let date: Date
        let day: String
        let value: Double
        var id: String { day }
    }

    private var rows: [Row] {
        TrendAnalysis.window(series.points, days: window.rawValue).compactMap { p in
            TrendAnalysis.date(p.day).map { Row(date: $0, day: p.day, value: p.value) }
        }
    }

    var body: some View {
        let rows = self.rows
        let values = rows.map(\.value)
        let band = series.band ?? UsualRange.band(values)
        let average = TrendAnalysis.mean(values)
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            chartCard(rows: rows, band: band, average: average)
            weekdayCard(rows: rows)
            analysisCard
            if let route = series.detailsRoute {
                NavigationLink { route.destination } label: {
                    GlanceLinkRow(title: String(localized: "All details"), icon: "chart.xyaxis.line")
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Chart

    private func chartCard(rows: [Row], band: ClosedRange<Double>?, average: Double?) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space3) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: rows.last.map { series.format($0.value) } ?? String(localized: "No data"))
                        .font(StrandFont.number(30))
                        .foregroundStyle(StrandPalette.textPrimary)
                    if let last = rows.last {
                        Text(verbatim: Self.dateText(last.date))
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                }
                Spacer()
                if let average {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(verbatim: series.format(average))
                            .font(StrandFont.number(18))
                            .foregroundStyle(series.tint)
                        Text("Average").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    }
                }
            }
            if rows.count >= 2 {
                chart(rows: rows, band: band, average: average)
                    .frame(height: 220)
            } else {
                Text("Not enough days in this range yet.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
            HStack(spacing: 6) {
                ForEach(Window.allCases) { w in
                    Button { withAnimation(.easeInOut(duration: 0.2)) { window = w } } label: {
                        Text(verbatim: w.label)
                            .font(StrandFont.subhead.weight(.semibold))
                            .foregroundStyle(window == w ? StrandPalette.textPrimary : StrandPalette.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(window == w ? StrandPalette.surfaceOverlay : .clear))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(window == w ? .isSelected : [])
                }
            }
            .padding(4)
            .background(Capsule().fill(StrandPalette.surfaceInset))
            if band != nil {
                Label {
                    Text(verbatim: series.band != nil ? String(localized: "Shaded: your normal range")
                         : String(localized: "Shaded: where most of these days fall"))
                } icon: {
                    RoundedRectangle(cornerRadius: 2).fill(series.tint.opacity(0.25)).frame(width: 14, height: 10)
                }
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textTertiary)
            }
        }
        .padding(NoopMetrics.cardPadding)
        .background(NoopPanelSurface(cornerRadius: NoopMetrics.cardRadius))
    }

    private func chart(rows: [Row], band: ClosedRange<Double>?, average: Double?) -> some View {
        let values = rows.map(\.value) + [band?.lowerBound, band?.upperBound].compactMap { $0 }
        let lo = values.min() ?? 0, hi = values.max() ?? 1
        let pad = max((hi - lo) * 0.12, 1e-6)
        let dense = rows.count > 45
        return Chart {
            if let band, let first = rows.first?.date, let last = rows.last?.date {
                RectangleMark(xStart: .value("Start", first), xEnd: .value("End", last),
                              yStart: .value("Low", band.lowerBound), yEnd: .value("High", band.upperBound))
                    .foregroundStyle(series.tint.opacity(0.18))
            }
            ForEach(rows) { r in
                LineMark(x: .value("Day", r.date), y: .value(series.title, r.value))
                    .foregroundStyle(series.tint)
                    .interpolationMethod(.monotone)
                if !dense {
                    PointMark(x: .value("Day", r.date), y: .value(series.title, r.value))
                        .foregroundStyle(series.tint)
                        .symbolSize(22)
                }
            }
            if let average {
                RuleMark(y: .value("Average", average))
                    .foregroundStyle(StrandPalette.textTertiary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }
        .chartYScale(domain: (lo - pad)...(hi + pad))
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { v in
                AxisGridLine().foregroundStyle(StrandPalette.hairline)
                AxisValueLabel {
                    if let d = v.as(Double.self) { Text(verbatim: series.format(d)) }
                }
                .foregroundStyle(StrandPalette.textTertiary)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    .foregroundStyle(StrandPalette.textTertiary)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                let plot = proxy.plotRectCompat(in: geo)
                ZStack(alignment: .topLeading) {
                    if let sx = selectedX, let r = nearest(rows, toX: sx - plot.minX, proxy: proxy),
                       let px = proxy.position(forX: r.date), let py = proxy.position(forY: r.value) {
                        let cx = px + plot.minX
                        CrosshairRule(x: cx, height: geo.size.height)
                        HighlightDot(color: series.tint).position(x: cx, y: py + plot.minY)
                        PositionedTooltip(anchor: CGPoint(x: cx, y: py + plot.minY), container: geo.size,
                                          tooltip: ChartTooltip(value: series.format(r.value),
                                                                label: Self.dateText(r.date)))
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { g in setSelection(g.location.x) }
                    .onEnded { _ in setSelection(nil) })
                .onContinuousHover(coordinateSpace: .local) { phase in
                    switch phase {
                    case .active(let p): setSelection(p.x)
                    case .ended: setSelection(nil)
                    }
                }
            }
        }
        .accessibilityLabel(Text(verbatim: series.title))
    }

    /// Selection without animation, so scrubbing never re-runs the line's draw-on.
    private func setSelection(_ x: CGFloat?) {
        var tx = Transaction()
        tx.disablesAnimations = true
        withTransaction(tx) { selectedX = x }
    }

    private func nearest(_ rows: [Row], toX x: CGFloat, proxy: ChartProxy) -> Row? {
        guard let date: Date = proxy.value(atX: x) else { return nil }
        return rows.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    // MARK: Weekday

    private func weekdayCard(rows: [Row]) -> some View {
        let means = TrendAnalysis.weekdayMeans(rows.map { ($0.day, $0.value) })
        let present = means.compactMap { $0 }
        let lo = present.min() ?? 0, hi = present.max() ?? 1
        let initials = GlanceMonthGrid.weekdayInitials
        return VStack(alignment: .leading, spacing: NoopMetrics.space3) {
            Text("By day of the week").font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
            HStack(alignment: .bottom, spacing: NoopMetrics.space2) {
                ForEach(0..<7, id: \.self) { i in
                    VStack(spacing: 6) {
                        let m = means[i]
                        let f = m.map { hi > lo ? 0.25 + 0.75 * ($0 - lo) / (hi - lo) : 0.6 } ?? 0
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(m == nil ? StrandPalette.surfaceInset
                                  : series.tint.opacity(m == hi ? 1 : 0.35 + 0.5 * f))
                            .frame(height: max(6, 70 * f))
                        Text(verbatim: initials[i]).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: "\(initials[i]): \(means[i].map(series.format) ?? "—")"))
                }
            }
            .frame(height: 96, alignment: .bottom)
            Text("Average for each weekday in the chosen range. The tallest bar is your highest day.")
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(NoopMetrics.cardPadding)
        .background(NoopPanelSurface(cornerRadius: NoopMetrics.cardRadius))
    }

    // MARK: Analysis

    private var analysisCard: some View {
        let changes = TrendAnalysis.changes(series.points)
        return VStack(alignment: .leading, spacing: 0) {
            Text("Trend analysis").font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                .padding(.bottom, NoopMetrics.space2)
            ForEach(changes, id: \.days) { c in
                HStack(spacing: NoopMetrics.space3) {
                    Text("\(c.days)-day")
                        .font(StrandFont.body)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .frame(width: 72, alignment: .leading)
                    if let d = c.delta {
                        Image(systemName: d > 0 ? "arrow.up.circle.fill" : (d < 0 ? "arrow.down.circle.fill" : "equal.circle.fill"))
                            .foregroundStyle(series.tint)
                        Text(verbatim: signed(d))
                            .font(StrandFont.bodyNumber)
                            .foregroundStyle(StrandPalette.textPrimary)
                    } else {
                        Text(verbatim: "—").foregroundStyle(StrandPalette.textTertiary)
                    }
                    Spacer()
                    GlanceSparkBand(values: TrendAnalysis.window(series.points, days: c.days * 2).map(\.value),
                                    band: nil, tint: series.tint)
                        .frame(width: 90, height: 28)
                }
                .padding(.vertical, NoopMetrics.space2)
                if c.days != changes.last?.days {
                    Rectangle().fill(StrandPalette.hairline).frame(height: 1)
                }
            }
            Text("The average of the last days compared with the same number of days before them.")
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, NoopMetrics.space2)
        }
        .padding(NoopMetrics.cardPadding)
        .background(NoopPanelSurface(cornerRadius: NoopMetrics.cardRadius))
    }

    private func signed(_ d: Double) -> String {
        let s = series.format(abs(d))
        return d > 0 ? "+\(s)" : (d < 0 ? "−\(s)" : s)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    /// A day key's date as "Thu 25 Sep", in the app's language (the date is UTC midnight of the key).
    static func dateText(_ d: Date) -> String {
        dateFormatter.locale = AppLanguage.activeLocale
        dateFormatter.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return dateFormatter.string(from: d)
    }
}

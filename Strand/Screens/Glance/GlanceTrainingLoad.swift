import SwiftUI
import Charts
import StrandDesign
import StrandAnalytics
import WhoopStore

// Glance's training load (#2463): the same CTL/ATL model the Trends card draws
// (`TrainingLoadCard.computeResult`, one engine run over the same day rows), in plain words and
// interactive. Fitness is the long-run average of daily Effort, fatigue the short-run one, and form the
// gap between them. The only verdict is the sign of form; no zones are invented.

struct GlanceTrainingLoadCard: View {
    let days: [DailyMetric]

    enum Window: Int, CaseIterable, Identifiable {
        case week = 7, month = 30, quarter = 90, all = 0
        var id: Int { rawValue }
        var label: String {
            switch self {
            case .week: return String(localized: "1W")
            case .month: return String(localized: "1M")
            case .quarter: return String(localized: "3M")
            case .all: return String(localized: "All")
            }
        }
    }

    private struct Row: Identifiable {
        let date: Date
        let fitness: Double
        let fatigue: Double
        var id: Date { date }
    }

    @State private var window: Window = .month
    @State private var selectedX: CGFloat?
    @State private var result: TrainingLoadEngine.Result?

    /// Form within this of zero reads as balanced rather than fresh or fatigued.
    private static let balancedBand = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space3) {
            if let result, result.points.count >= 2 {
                content(result)
            } else {
                Text("Training load needs \(TrainingLoadEngine.Configuration.standard.minimumDays) days of Effort in a row to begin.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(NoopMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NoopPanelSurface(cornerRadius: NoopMetrics.cardRadius))
        .task(id: key) {
            result = TrainingLoadCard.computeResult(days: days)
        }
    }

    private var key: String { "\(days.count)-\(days.last?.day ?? "")-\(days.last?.strain ?? -1)" }

    @ViewBuilder private func content(_ r: TrainingLoadEngine.Result) -> some View {
        let rows = rows(r)
        let shown = scrubbedRow ?? rows.last
        if let shown {
            let form = shown.fitness - shown.fatigue
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: formWords(form))
                        .font(StrandFont.headline)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text(verbatim: GlanceTrendSections.dateText(shown.date))
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
                Spacer()
                if r.state == .building {
                    Text("Building \(r.contiguousDays) of \(TrainingLoadEngine.Configuration.standard.establishedDays) days")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
            }
            HStack(spacing: 0) {
                stat(String(localized: "Fitness"), shown.fitness, StrandPalette.effortColor)
                stat(String(localized: "Fatigue"), shown.fatigue, StrandPalette.metricAmber)
                stat(String(localized: "Form"), form, StrandPalette.textPrimary, signed: true)
            }
        }
        chart(rows)
            .frame(height: 170)
        HStack(spacing: 6) {
            ForEach(Window.allCases) { w in
                Button { withAnimation(.easeInOut(duration: 0.2)) { window = w } } label: {
                    Text(verbatim: w.label)
                        .font(StrandFont.subhead.weight(.semibold))
                        .foregroundStyle(window == w ? StrandPalette.textPrimary : StrandPalette.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(window == w ? StrandPalette.surfaceOverlay : .clear))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(window == w ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Capsule().fill(StrandPalette.surfaceInset))
        Text("Fitness is your average daily Effort over about six weeks; fatigue is the same over about a week. Form is fitness minus fatigue: above zero you are fresher than your training, below zero you are carrying fatigue from recent days.")
            .font(StrandFont.caption)
            .foregroundStyle(StrandPalette.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func formWords(_ form: Double) -> String {
        if form > Self.balancedBand { return String(localized: "Fresher than your training") }
        if form < -Self.balancedBand { return String(localized: "Carrying fatigue") }
        return String(localized: "Balanced")
    }

    private func stat(_ label: String, _ v: Double, _ tint: Color, signed: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: signed ? String(format: "%+.1f", locale: AppLanguage.activeLocale, v)
                                  : String(format: "%.1f", locale: AppLanguage.activeLocale, v))
                .font(StrandFont.number(20))
                .foregroundStyle(tint)
            Text(verbatim: label).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func rows(_ r: TrainingLoadEngine.Result) -> [Row] {
        let all = r.points.compactMap { p in
            TrendAnalysis.date(p.day).map { Row(date: $0, fitness: p.chronicLoad, fatigue: p.acuteLoad) }
        }
        return window == .all ? all : Array(all.suffix(window.rawValue))
    }

    private func chart(_ rows: [Row]) -> some View {
        let values = rows.flatMap { [$0.fitness, $0.fatigue] }
        let lo = values.min() ?? 0, hi = values.max() ?? 1
        let pad = max((hi - lo) * 0.15, 1)
        return Chart {
            ForEach(rows) { r in
                LineMark(x: .value("Day", r.date), y: .value("Load", r.fitness), series: .value("Line", "fitness"))
                    .foregroundStyle(StrandPalette.effortColor)
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Day", r.date), y: .value("Load", r.fatigue), series: .value("Line", "fatigue"))
                    .foregroundStyle(StrandPalette.metricAmber)
                    .interpolationMethod(.monotone)
            }
        }
        .chartYScale(domain: (lo - pad)...(hi + pad))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    .foregroundStyle(StrandPalette.textTertiary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(StrandPalette.hairline)
                AxisValueLabel().foregroundStyle(StrandPalette.textTertiary)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                let plot = proxy.plotRectCompat(in: geo)
                ZStack(alignment: .topLeading) {
                    if let sx = selectedX, let r = nearest(rows, sx - plot.minX, proxy),
                       let px = proxy.position(forX: r.date) {
                        CrosshairRule(x: px + plot.minX, height: geo.size.height)
                        if let y1 = proxy.position(forY: r.fitness) {
                            HighlightDot(color: StrandPalette.effortColor).position(x: px + plot.minX, y: y1 + plot.minY)
                        }
                        if let y2 = proxy.position(forY: r.fatigue) {
                            HighlightDot(color: StrandPalette.metricAmber).position(x: px + plot.minX, y: y2 + plot.minY)
                        }
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { g in scrub(g.location.x, rows, plot, proxy) }
                    .onEnded { _ in scrub(nil, rows, plot, proxy) })
                .onContinuousHover(coordinateSpace: .local) { phase in
                    switch phase {
                    case .active(let p): scrub(p.x, rows, plot, proxy)
                    case .ended: scrub(nil, rows, plot, proxy)
                    }
                }
            }
        }
        .accessibilityLabel(Text("Training load"))
    }

    private func nearest(_ rows: [Row], _ x: CGFloat, _ proxy: ChartProxy) -> Row? {
        guard let d: Date = proxy.value(atX: x) else { return nil }
        return rows.min { abs($0.date.timeIntervalSince(d)) < abs($1.date.timeIntervalSince(d)) }
    }

    /// The day under the finger, so the headline and stats follow the scrub; nil shows the latest day.
    @State private var scrubbedRow: Row?

    private func scrub(_ x: CGFloat?, _ rows: [Row], _ plot: CGRect, _ proxy: ChartProxy) {
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            selectedX = x
            scrubbedRow = x.flatMap { nearest(rows, $0 - plot.minX, proxy) }
        }
    }
}

import SwiftUI
import StrandDesign
import WhoopStore

// Glance's consistency cards on Trends (#2463): workouts per day over the last two months, and how many
// recent days landed in their Effort target. Both read `ActivityConsistency`, which counts the saved
// workouts and the stored day rows; nothing here is scored afresh.

/// Workouts per calendar day for the last two months. Opens the workout list.
struct GlanceActivityCalendarCard: View {
    @EnvironmentObject private var repo: Repository
    @State private var months: [ActivityConsistency.Month] = []

    var body: some View {
        NavigationLink(value: TabRoute.workouts) {
            VStack(alignment: .leading, spacing: NoopMetrics.space4) {
                HStack {
                    Text("Activity").font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                    Spacer()
                    GlanceChevron()
                }
                HStack(alignment: .top, spacing: NoopMetrics.space5) {
                    ForEach(months, id: \.start) { month in
                        GlanceMonthGrid(month: month)
                    }
                }
                HStack(spacing: NoopMetrics.space4) {
                    legend(1, String(localized: "1 workout"))
                    legend(2, String(localized: "2 workouts"))
                    legend(3, String(localized: "3+ workouts"))
                }
            }
            .padding(NoopMetrics.cardPadding)
            .background(NoopPanelSurface(cornerRadius: NoopMetrics.cardRadius))
            .contentShape(Rectangle())
        }
        .buttonStyle(LiquidPressStyle())
        .task(id: repo.refreshSeq) {
            let starts = await repo.workoutRows(days: 62).map(\.startTs)
            months = ActivityConsistency.months(workoutStarts: starts, now: Date())
        }
    }

    private func legend(_ count: Int, _ label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(GlanceMonthGrid.fill(count)).frame(width: 8, height: 8)
            Text(verbatim: label).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
        }
    }
}

/// One month: weekday initials over a grid of day bars, each coloured by that day's workout count.
struct GlanceMonthGrid: View {
    let month: ActivityConsistency.Month

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            Text(verbatim: title).font(StrandFont.subhead.weight(.semibold)).foregroundStyle(StrandPalette.textPrimary)
            LazyVGrid(columns: Self.columns, spacing: 6) {
                ForEach(Array(Self.weekdayInitials.enumerated()), id: \.offset) { _, s in
                    Text(verbatim: s).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                }
                ForEach(0..<month.leadingBlanks, id: \.self) { _ in Color.clear.frame(height: 8) }
                ForEach(month.cells, id: \.day) { c in
                    Capsule()
                        .fill(c.isFuture ? StrandPalette.surfaceInset.opacity(0.4) : Self.fill(c.workouts))
                        .frame(height: 8)
                        .overlay(Capsule().strokeBorder(c.isToday ? StrandPalette.textPrimary : .clear, lineWidth: 1.5))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(title): \(String(localized: "\(activeDays) active days"))"))
    }

    private var activeDays: Int { month.cells.filter { $0.workouts > 0 }.count }

    private var title: String {
        let f = DateFormatter()
        f.locale = AppLanguage.activeLocale
        f.setLocalizedDateFormatFromTemplate("MMMyyyy")
        return f.string(from: month.start)
    }

    /// Weekday initials starting from the calendar's first weekday, matching the grid's columns.
    static var weekdayInitials: [String] {
        var cal = Calendar.current
        cal.locale = AppLanguage.activeLocale
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let first = Calendar.current.firstWeekday - 1
        return (0..<7).map { symbols[(first + $0) % 7] }
    }

    static func fill(_ workouts: Int) -> Color {
        switch workouts {
        case 0:  return StrandPalette.surfaceInset
        case 1:  return StrandPalette.effortColor.opacity(0.55)
        case 2:  return StrandPalette.effortColor
        default: return StrandPalette.effortBright
        }
    }
}

/// How many of the last 30 finished days landed in the Effort target their Charge set.
struct GlanceTargetHistoryCard: View {
    @EnvironmentObject private var repo: Repository

    var body: some View {
        let t = ActivityConsistency.targetDays(repo.days, before: Repository.logicalDayKey(Date()))
        VStack(alignment: .leading, spacing: NoopMetrics.space3) {
            Text("Effort target").font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
            if t.total == 0 {
                Text("No days with both a Charge and an Effort yet.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textTertiary)
            } else {
                Text("\(t.within) of \(t.total) days within target")
                    .font(StrandFont.number(24))
                    .foregroundStyle(StrandPalette.textPrimary)
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        segment(t.below, t.total, geo.size.width, StrandPalette.effortColor.opacity(0.35))
                        segment(t.within, t.total, geo.size.width, StrandPalette.statusPositive)
                        segment(t.above, t.total, geo.size.width, StrandPalette.statusWarning)
                    }
                }
                .frame(height: 10)
                .clipShape(Capsule())
                .accessibilityHidden(true)
                HStack(spacing: NoopMetrics.space4) {
                    legend(StrandPalette.effortColor.opacity(0.35), String(localized: "Below: \(t.below)"))
                    legend(StrandPalette.statusPositive, String(localized: "Within: \(t.within)"))
                    legend(StrandPalette.statusWarning, String(localized: "Above: \(t.above)"))
                }
                Text("Each day is judged against the target its own Charge set. Today is left out until it ends.")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(NoopMetrics.cardPadding)
        .background(NoopPanelSurface(cornerRadius: NoopMetrics.cardRadius))
    }

    @ViewBuilder
    private func segment(_ n: Int, _ total: Int, _ width: CGFloat, _ color: Color) -> some View {
        if n > 0 {
            Rectangle().fill(color).frame(width: max(0, width * CGFloat(n) / CGFloat(max(total, 1)) - 2))
        }
    }

    private func legend(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(verbatim: label).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
        }
    }
}

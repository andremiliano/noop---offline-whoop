import Foundation
import WhoopStore

/// How consistently the wearer has trained (#2463 Glance): workouts per calendar day, and how many recent
/// days landed in the Effort target their Charge set.
///
/// Descriptive only. Counts come from the saved workout list and the stored day rows; the target band is
/// `EffortTarget`'s, which is NOOP's existing recovery → optimal-strain mapping, so a day judged here is
/// judged the way the Effort page judges today.
enum ActivityConsistency {

    /// One calendar day in a month grid.
    struct Cell: Equatable {
        /// Day of the month, 1-based.
        let day: Int
        /// Workouts that started on this day.
        let workouts: Int
        let isToday: Bool
        let isFuture: Bool
    }

    /// One month laid out for a grid that starts on the calendar's first weekday.
    struct Month: Equatable {
        /// The first day of the month.
        let start: Date
        /// Empty slots before day 1, so day 1 lands under its weekday.
        let leadingBlanks: Int
        let cells: [Cell]
    }

    /// The `count` calendar months ending with the one containing `now`, oldest first.
    static func months(workoutStarts: [Int], now: Date, count: Int = 2,
                       calendar: Calendar = .current) -> [Month] {
        // Keyed yyyymmdd on the given calendar: DateComponents' own equality also compares fields a
        // calendar may or may not fill in, which a hand-built key would not match.
        func key(_ y: Int?, _ m: Int?, _ d: Int?) -> Int { (y ?? 0) * 10_000 + (m ?? 0) * 100 + (d ?? 0) }
        var perDay: [Int: Int] = [:]
        for ts in workoutStarts {
            let c = calendar.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: TimeInterval(ts)))
            perDay[key(c.year, c.month, c.day), default: 0] += 1
        }
        let today = calendar.dateComponents([.year, .month, .day], from: now)
        guard let thisMonth = calendar.date(from: DateComponents(year: today.year, month: today.month, day: 1)) else {
            return []
        }
        return (0..<max(count, 1)).reversed().compactMap { back -> Month? in
            guard let start = calendar.date(byAdding: .month, value: -back, to: thisMonth),
                  let range = calendar.range(of: .day, in: .month, for: start) else { return nil }
            let weekday = calendar.component(.weekday, from: start)
            let blanks = (weekday - calendar.firstWeekday + 7) % 7
            let ym = calendar.dateComponents([.year, .month], from: start)
            let cells = range.map { d -> Cell in
                let k = key(ym.year, ym.month, d)
                let isToday = k == key(today.year, today.month, today.day)
                let isFuture = back == 0 && d > (today.day ?? 0)
                return Cell(day: d, workouts: perDay[k] ?? 0, isToday: isToday, isFuture: isFuture)
            }
            return Month(start: start, leadingBlanks: blanks, cells: cells)
        }
    }

    /// Recent days against their own Effort target.
    struct TargetDays: Equatable {
        var below = 0
        var within = 0
        var above = 0
        var total: Int { below + within + above }
    }

    /// The last `window` scored days before `beforeKey`, each judged against the target its own Charge
    /// set. Today is left out because its Effort is still accruing; a day without both a Charge and an
    /// Effort is not counted.
    static func targetDays(_ days: [DailyMetric], before beforeKey: String, window: Int = 30) -> TargetDays {
        var out = TargetDays()
        let scored = days
            .filter { $0.day < beforeKey && $0.recovery != nil && $0.strain != nil }
            .sorted { $0.day < $1.day }
            .suffix(window)
        for d in scored {
            // Judged on the 0–21 axis the band is defined on; the scale only changes how it is shown.
            let band = EffortTarget.band(charge: d.recovery, scale: .whoop)
            let effort = d.strain.map { UnitFormatter.effortValue($0, scale: .whoop) }
            switch EffortTarget.standing(effort: effort, band: band) {
            case .below: out.below += 1
            case .within: out.within += 1
            case .above: out.above += 1
            case nil: break
            }
        }
        return out
    }
}

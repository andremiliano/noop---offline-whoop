import Foundation
import StrandAnalytics

/// Tonight's sleep plan (#2463 Glance): how much sleep to aim for, and when to be asleep to get it before
/// the wearer's wake time.
///
/// Nothing new is scored. The need is the Sleep tab's own: the sleep-debt ledger's base need, plus the
/// debt it says to add tonight (`SleepDebtLedgerCard`: "Add about … to your base sleep target
/// tonight"), with the same on-target deadband. The wake time is the one the wind-down reminder
/// schedules from when the wearer has set one, so the bedtime shown and the reminder that fires are
/// worked out from one setting; otherwise it is the wearer's usual wake time, the median end of their
/// recent main sleeps, and the card says which it used.
enum TonightPlan {

    enum WakeSource: Equatable {
        /// The wind-down reminder's wake time.
        case setting
        /// The median end of recent main sleeps.
        case usual
    }

    /// Main sleeps counted toward the usual wake time: at least this long, so naps do not pull it.
    static let mainSleepMinSeconds = 3 * 3600
    /// Recent main sleeps the usual wake time is the median of, and the fewest it needs.
    static let usualWakeNights = 14
    static let usualWakeMinNights = 3

    /// The wearer's usual wake time, in minutes after midnight on `calendar`: the median end of their
    /// last `usualWakeNights` main sleeps, or nil with fewer than `usualWakeMinNights`. Wake times
    /// after noon are read as the previous night's late sleep and left out.
    static func usualWakeMinutes(_ sleeps: [(startTs: Int, endTs: Int)], calendar: Calendar = .current) -> Int? {
        let ends = sleeps
            .filter { $0.endTs - $0.startTs >= mainSleepMinSeconds }
            .sorted { $0.endTs < $1.endTs }
            .suffix(usualWakeNights)
            .map { s -> Int in
                let c = calendar.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: TimeInterval(s.endTs)))
                return (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }
            .filter { $0 < 12 * 60 }
            .sorted()
        guard ends.count >= usualWakeMinNights else { return nil }
        let mid = ends.count / 2
        return ends.count % 2 == 1 ? ends[mid] : (ends[mid - 1] + ends[mid]) / 2
    }

    struct Plan: Equatable {
        /// Sleep to aim for tonight, in minutes: `baseMin + makeUpMin`.
        let needMin: Double
        /// The ledger's base need.
        let baseMin: Double
        /// Debt to make up tonight, or 0 when the ledger is on target.
        let makeUpMin: Double
        /// The next wake time, when one is known.
        let wake: Date?
        /// Where `wake` came from, nil without one.
        let wakeSource: WakeSource?
        /// When to be asleep to get `needMin` before `wake`.
        let asleepBy: Date?
    }

    /// The plan at `now`, or nil without a ledger.
    ///
    /// - Parameters:
    ///   - wakeMinutes: minutes after midnight the wearer wakes on a Calendar weekday (1 = Sunday), from
    ///     their wind-down setting, or nil when none is set.
    ///   - usualWake: the usual wake time (`usualWakeMinutes`), used when there is no setting.
    static func plan(ledger: SleepDebtLedger?, wakeMinutes: ((Int) -> Int)?, usualWake: Int? = nil,
                     now: Date, calendar: Calendar = .current) -> Plan? {
        guard let ledger else { return nil }
        let makeUp = ledger.isDebt && ledger.magnitudeMin >= SleepDebt.onTargetBandMin ? ledger.magnitudeMin : 0
        let need = ledger.needMin + makeUp
        let source: WakeSource? = wakeMinutes != nil ? .setting : (usualWake != nil ? .usual : nil)
        let minutes: ((Int) -> Int)? = wakeMinutes ?? usualWake.map { usual in { _ in usual } }
        let wake = minutes.flatMap { nextWake(after: now, wakeMinutes: $0, calendar: calendar) }
        return Plan(needMin: need, baseMin: ledger.needMin, makeUpMin: makeUp, wake: wake,
                    wakeSource: wake == nil ? nil : source,
                    asleepBy: wake.map { $0.addingTimeInterval(-need * 60) })
    }

    /// The first wake time after `now`: today's if it is still ahead, else tomorrow's.
    static func nextWake(after now: Date, wakeMinutes: (Int) -> Int, calendar: Calendar) -> Date? {
        let today = calendar.startOfDay(for: now)
        for offset in 0...1 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let minutes = wakeMinutes(calendar.component(.weekday, from: day))
            if let t = calendar.date(byAdding: .minute, value: minutes, to: day), t > now { return t }
        }
        return nil
    }
}

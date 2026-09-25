import Foundation
import StrandAnalytics

/// Tonight's sleep plan (#2463 Glance): how much sleep to aim for, and — when the wearer has set a wake
/// time — when to be asleep to get it.
///
/// Nothing new is scored. The need is the Sleep tab's own: the sleep-debt ledger's base need, plus the
/// debt it says to add tonight (`SleepDebtLedgerCard`: "Add about … to your base sleep target
/// tonight"), with the same on-target deadband. The wake time is the one the wind-down reminder
/// schedules from, so the bedtime shown and the reminder that fires are worked out from one setting.
enum TonightPlan {

    struct Plan: Equatable {
        /// Sleep to aim for tonight, in minutes: `baseMin + makeUpMin`.
        let needMin: Double
        /// The ledger's base need.
        let baseMin: Double
        /// Debt to make up tonight, or 0 when the ledger is on target.
        let makeUpMin: Double
        /// The next wake time, when one is set.
        let wake: Date?
        /// When to be asleep to get `needMin` before `wake`.
        let asleepBy: Date?
    }

    /// The plan at `now`, or nil without a ledger.
    ///
    /// - Parameter wakeMinutes: minutes after midnight the wearer wakes on a Calendar weekday (1 = Sunday),
    ///   or nil when no wake time is set.
    static func plan(ledger: SleepDebtLedger?, wakeMinutes: ((Int) -> Int)?, now: Date,
                     calendar: Calendar = .current) -> Plan? {
        guard let ledger else { return nil }
        let makeUp = ledger.isDebt && ledger.magnitudeMin >= SleepDebt.onTargetBandMin ? ledger.magnitudeMin : 0
        let need = ledger.needMin + makeUp
        let wake = wakeMinutes.flatMap { nextWake(after: now, wakeMinutes: $0, calendar: calendar) }
        return Plan(needMin: need, baseMin: ledger.needMin, makeUpMin: makeUp, wake: wake,
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

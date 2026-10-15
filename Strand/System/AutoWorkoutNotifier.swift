import Foundation
import UserNotifications

/// A notification when a sync turns up a stretch that looks like a workout (the opt-in "Auto-detect workouts"
/// setting), so the suggestion on Today is not found by chance. It only ever suggests: the notification saves
/// nothing, and the card on Today stays the place to save it, pick its sport, or dismiss it.
enum AutoWorkoutNotifier {

    /// Pure, so `StrandTests` covers it.
    enum Policy {
        /// A stretch that ended less than this long ago may still be going, or just have slowed, and its end
        /// would move on the next scan: it is not announced until the heart rate has been down this long.
        static let settleSeconds = 10 * 60
        /// One that ended longer ago than this is not news.
        static let staleAfterSeconds = 12 * 3600

        /// Whether to announce a stretch `startSec...endSec`, given the last one announced. A stretch that
        /// overlaps the last announced is the same session seen again with shifted edges, never a new one.
        static func shouldNotify(enabled: Bool, startSec: Int, endSec: Int,
                                 lastNotified: (start: Int, end: Int)?, now: Int) -> Bool {
            guard enabled, endSec > startSec else { return false }
            let age = now - endSec
            guard age >= settleSeconds, age <= staleAfterSeconds else { return false }
            if let last = lastNotified, startSec < last.end, last.start < endSec { return false }
            return true
        }
    }

    private static let lastKey = "behavior.autoWorkoutLastNotified"   // "start:end"
    private static let lastScanKey = "behavior.autoWorkoutLastScan"
    /// Scans are not free (two days of heart rate), so one per this long at most.
    static let scanSpacingSeconds = 10 * 60

    /// Ask when the setting is switched on, so the system prompt comes at a predictable moment.
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static var scanIsDue: Bool {
        let last = UserDefaults.standard.double(forKey: lastScanKey)
        return Date().timeIntervalSince1970 - last >= Double(scanSpacingSeconds)
    }

    static func markScanned() { UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastScanKey) }

    private static var lastNotified: (start: Int, end: Int)? {
        guard let raw = UserDefaults.standard.string(forKey: lastKey) else { return nil }
        let p = raw.split(separator: ":").compactMap { Int($0) }
        return p.count == 2 ? (p[0], p[1]) : nil
    }

    /// Posts at most one notification for `candidate`, and remembers it so it is not announced twice.
    static func onCandidate(startSec: Int, endSec: Int, durationMin: Int, avgBpm: Int, enabled: Bool) {
        let now = Int(Date().timeIntervalSince1970)
        guard Policy.shouldNotify(enabled: enabled, startSec: startSec, endSec: endSec,
                                  lastNotified: lastNotified, now: now) else { return }
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        let from = f.string(from: Date(timeIntervalSince1970: TimeInterval(startSec)))
        let to = f.string(from: Date(timeIntervalSince1970: TimeInterval(endSec)))
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Looks like a workout")
            content.body = String(localized: "\(from)-\(to), \(durationMin) min, avg HR \(avgBpm). Open NOOP to save it.")
            content.sound = .default
            center.add(UNNotificationRequest(identifier: "auto-workout", content: content, trigger: nil))
            UserDefaults.standard.set("\(startSec):\(endSec)", forKey: lastKey)
        }
    }
}

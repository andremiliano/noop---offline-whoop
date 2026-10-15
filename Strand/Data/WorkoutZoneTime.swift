import Foundation

/// How a zone's time reads on the live workout screen: "45s", "12m", "1h05"; empty for none. The seconds
/// themselves come from `HRZones.timeInZone`, the same source the saved workout's zones use.
enum WorkoutZoneTime {
    static func text(_ seconds: Int) -> String {
        if seconds <= 0 { return "" }
        if seconds < 60 { return "\(seconds)s" }
        let m = seconds / 60
        return m < 60 ? "\(m)m" : String(format: "%dh%02d", m / 60, m % 60)
    }
}

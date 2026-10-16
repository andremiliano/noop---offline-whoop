import Foundation
import StrandAnalytics

/// What a stretch must look like before NOOP suggests it as a workout, on top of the detector's own rule.
///
/// The detector flags 12 minutes at or above resting + 30 bpm, which a brisk walk, stairs or a stressful
/// stretch clears: a notification for a 22-minute average of 93 bpm (resting 50) was not a workout. The
/// suggestion now also needs the stretch's AVERAGE well above resting, and a peak clearly in exercise range.
/// A strength session averages around resting + 60 and a run well above, so both clear it. Applied here, in
/// the app, to the detector's result: the detector itself is shared with Android and left as it is.
enum AutoWorkoutGate {
    /// Average heart rate over the stretch, above resting.
    static let minAvgAboveResting = 50
    /// Peak heart rate over the stretch, above resting.
    static let minPeakAboveResting = 70

    /// Whether to show a stretch on the Today card: it clears the bar, or it is one the wearer was already
    /// NOTIFIED about. The second half is the point: a notification promises a suggestion to say yes or no to,
    /// for as long as it takes to get to it, so it must not vanish because the bar was raised since, or because
    /// the stretch's edges moved a little.
    static func keeps(_ w: DetectedWorkout, restingBpm: Int?, notified: (start: Int, end: Int)?) -> Bool {
        if passes(w, restingBpm: restingBpm) { return true }
        guard let n = notified else { return false }
        return w.startSec < n.end && n.start < w.endSec
    }

    static func passes(_ w: DetectedWorkout, restingBpm: Int?) -> Bool {
        let rest = restingBpm ?? AutoWorkoutDetector.defaultRestingHR
        return w.avgBpm >= rest + minAvgAboveResting && w.peakBpm >= rest + minPeakAboveResting
    }
}

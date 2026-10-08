import Foundation
import WhoopStore

/// Which rows the Apple Health workout write-back writes.
///
/// Health's copy of a workout is keyed by its START time alone (`HealthWriteback.appleHealthWorkoutKey`),
/// but the rows were de-duplicated on start AND sport. The same session held under two or three sport
/// labels (a detected bout, a relabelled manual row, an import) therefore produced several rows sharing
/// one Health key: the delete-then-write cleared the old copies once and then saved every row, so Health
/// held the same session two or three times and any reader that lists workouts (Bevel) showed it that
/// many times. One session, one Health workout.
enum WorkoutWritebackSelection {

    /// One row per start time. A row the wearer or an import named (anything but an auto-detected bout)
    /// beats a detected one; then the longer session wins; on a tie the later row in `rows` wins, which
    /// is the order the caller already used (computed first, then the store's own rows).
    static func onePerStart(_ rows: [WorkoutRow]) -> [WorkoutRow] {
        var byStart: [Int: WorkoutRow] = [:]
        for row in rows {
            if let current = byStart[row.startTs], !prefers(row, over: current) { continue }
            byStart[row.startTs] = row
        }
        return byStart.values.sorted { $0.startTs < $1.startTs }
    }

    private static func prefers(_ a: WorkoutRow, over b: WorkoutRow) -> Bool {
        let aDetected = WorkoutSource.classify(a.source) == .detected
        let bDetected = WorkoutSource.classify(b.source) == .detected
        if aDetected != bDetected { return !aDetected }
        let aLen = a.endTs - a.startTs, bLen = b.endTs - b.startTs
        if aLen != bLen { return aLen > bLen }
        return true
    }
}

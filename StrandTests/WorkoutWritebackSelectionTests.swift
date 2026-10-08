import XCTest
import WhoopStore
@testable import Strand

/// One session held under several sport labels must reach Apple Health once: its Health key is the start
/// time alone, so every extra row would be saved under the same key.
final class WorkoutWritebackSelectionTests: XCTestCase {

    private func row(_ start: Int, _ end: Int, sport: String, source: String) -> WorkoutRow {
        WorkoutRow(startTs: start, endTs: end, sport: sport, source: source, durationS: Double(end - start),
                   energyKcal: 492, avgHr: nil, maxHr: nil, strain: nil, distanceM: nil,
                   zonesJSON: nil, notes: nil, steps: nil)
    }

    func testSameStartUnderThreeLabelsIsWrittenOnce() {
        let rows = WorkoutWritebackSelection.onePerStart([
            row(1000, 4360, sport: "detected", source: "my-whoop-noop"),
            row(1000, 4360, sport: "Activity", source: "my-whoop"),
            row(1000, 4360, sport: "Running", source: "manual"),
        ])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].sport, "Running", "a named row beats a detected bout")
    }

    func testDistinctStartsAreAllKeptInOrder() {
        let rows = WorkoutWritebackSelection.onePerStart([
            row(5000, 6000, sport: "Cycling", source: "manual"),
            row(1000, 2000, sport: "Running", source: "manual"),
        ])
        XCTAssertEqual(rows.map(\.startTs), [1000, 5000])
    }

    func testLongerSessionWinsBetweenTwoNamedRows() {
        let rows = WorkoutWritebackSelection.onePerStart([
            row(1000, 1200, sport: "Running", source: "manual"),
            row(1000, 4000, sport: "Activity", source: "my-whoop"),
        ])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].endTs, 4000)
    }
}

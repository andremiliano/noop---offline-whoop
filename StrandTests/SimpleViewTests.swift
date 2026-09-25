import XCTest
@testable import Strand

/// #2463 Simple view and the strap setup guide. Both are pure, so what Simple view shows and what the
/// guide tells each strap to turn on are pinned here rather than read off the screen.
final class SimpleViewTests: XCTestCase {

    // MARK: - SimpleViewPrefs.order

    func testKeepsOnlyTheThreeSectionsInTheSavedOrder() {
        let full: [TodaySection] = [.keyMetrics, .workouts, .heartRate, .hero, .synthesis, .journal]
        XCTAssertEqual(SimpleViewPrefs.order(fullOrder: full), [.workouts, .hero, .synthesis])
    }

    func testAppendsAKeptSectionMissingFromAnOldSavedOrder() {
        // A saved order from before a section existed must not leave Simple view without it.
        XCTAssertEqual(SimpleViewPrefs.order(fullOrder: [.synthesis, .keyMetrics]),
                       [.synthesis, .hero, .workouts])
    }

    func testEmptyOrderYieldsTheCanonicalThree() {
        XCTAssertEqual(SimpleViewPrefs.order(fullOrder: []), [.hero, .synthesis, .workouts])
    }

    // MARK: - StrapSetupGuide

    private func defaults() -> UserDefaults {
        let name = "SimpleViewTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    func testFamilyFromSelectedModel() {
        XCTAssertEqual(StrapSetupGuide.Family.forSelectedModel(WhoopModel.whoop5mg.rawValue), .whoop5)
        XCTAssertEqual(StrapSetupGuide.Family.forSelectedModel(WhoopModel.whoop4.rawValue), .whoop4)
        XCTAssertEqual(StrapSetupGuide.Family.forSelectedModel(""), .whoop4)
    }

    /// The finding behind #2464: on 5/MG the strap alarm needs Protocol probes in Test Centre; on 4.0 it
    /// needs nothing switched on.
    func testAlarmRequirementDiffersByGeneration() {
        let five = StrapSetupGuide.items(for: .whoop5, includesAppleHealth: true).first { $0.id == "alarm" }
        let four = StrapSetupGuide.items(for: .whoop4, includesAppleHealth: true).first { $0.id == "alarm" }
        XCTAssertEqual(five?.requirement,
                       .toggle(key: PuffinExperiment.defaultsKey, place: .testCentre, control: "Protocol probes"))
        XCTAssertEqual(four?.requirement, .builtIn(place: .alarms))
    }

    func testBroadcastHeartRateOnlyForFiveSeries() {
        XCTAssertTrue(StrapSetupGuide.items(for: .whoop5, includesAppleHealth: true).contains { $0.id == "broadcastHr" })
        XCTAssertFalse(StrapSetupGuide.items(for: .whoop4, includesAppleHealth: true).contains { $0.id == "broadcastHr" })
    }

    func testBloodOxygenIsUnavailableOnFiveSeriesAndBuiltInOnFour() {
        let five = StrapSetupGuide.items(for: .whoop5, includesAppleHealth: true).first { $0.id == "bloodOxygen" }
        let four = StrapSetupGuide.items(for: .whoop4, includesAppleHealth: true).first { $0.id == "bloodOxygen" }
        if case .unavailable = five?.requirement {} else { XCTFail("5/MG SpO2 must read as unavailable") }
        XCTAssertEqual(four?.requirement, .builtIn(place: nil))
    }

    func testAppleHealthGoalOnlyWhereHealthExists() {
        XCTAssertTrue(StrapSetupGuide.items(for: .whoop5, includesAppleHealth: true).contains { $0.id == "healthWater" })
        XCTAssertFalse(StrapSetupGuide.items(for: .whoop5, includesAppleHealth: false).contains { $0.id == "healthWater" })
    }

    func testStatusReadsTheControlsOwnKeys() {
        let d = defaults()
        let items = StrapSetupGuide.items(for: .whoop5, includesAppleHealth: true)
        let hrv = items.first { $0.id == "overnightHrv" }!
        let scale = items.first { $0.id == "effortScale" }!

        XCTAssertEqual(StrapSetupGuide.status(of: hrv, defaults: d), .off)
        d.set(true, forKey: PuffinExperiment.keepRealtimeForDataKey)
        XCTAssertEqual(StrapSetupGuide.status(of: hrv, defaults: d), .on)

        XCTAssertEqual(StrapSetupGuide.status(of: scale, defaults: d), .off)
        d.set(EffortScale.whoop.rawValue, forKey: UnitPrefs.effortScaleKey)
        XCTAssertEqual(StrapSetupGuide.status(of: scale, defaults: d), .on)
    }

    /// Built-in and unavailable goals are not counted: the wearer has nothing to switch on for them.
    func testProgressCountsOnlySwitchableGoals() {
        let d = defaults()
        let items = StrapSetupGuide.items(for: .whoop5, includesAppleHealth: true)
        let switchable = items.filter {
            switch $0.requirement {
            case .toggle, .choice: return true
            default: return false
            }
        }.count
        XCTAssertEqual(StrapSetupGuide.progress(items, defaults: d).of, switchable)
        XCTAssertEqual(StrapSetupGuide.progress(items, defaults: d).on, 0)
        d.set(true, forKey: PuffinExperiment.defaultsKey)
        XCTAssertEqual(StrapSetupGuide.progress(items, defaults: d).on, 1)
    }
}

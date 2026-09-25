import Foundation

/// A plain-language map from "what I want to see" to "what to turn on", per strap generation (#2463,
/// #2465). Several settings decide whether a feature works at all, and they live in different screens
/// under names that do not say what they gate; this lists them in one place against the wearer's goal.
///
/// Pure and UI-free so the mapping is pinned by tests. It READS setting state and never writes it:
/// several of these switches do more than flip a flag when changed from their own screen (continuous HRV
/// re-arms the stream, broadcast HR writes to the strap), so the guide links to those screens rather
/// than toggling behind their back.
enum StrapSetupGuide {

    /// WHOOP generations that need different setup. 5.0 and MG share one protocol and one model value
    /// (`WhoopModel.whoop5mg`), so they share one guide.
    enum Family: String, CaseIterable, Identifiable {
        case whoop4
        case whoop5

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .whoop4: return "WHOOP 4.0"
            case .whoop5: return "WHOOP 5.0 / MG"
            }
        }

        /// The family for the persisted `selectedWhoopModel` value. Anything that is not the 5/MG value
        /// reads as 4.0, matching the app's own default model.
        static func forSelectedModel(_ raw: String) -> Family {
            raw == WhoopModel.whoop5mg.rawValue ? .whoop5 : .whoop4
        }
    }

    /// The screen that owns a control.
    enum Place: Hashable {
        case settings
        case testCentre
        case alarms

        var title: String {
            switch self {
            case .settings:   return String(localized: "Settings")
            case .testCentre: return String(localized: "More › Test Centre")
            case .alarms:     return String(localized: "More › Alarms")
            }
        }
    }

    /// What a goal needs on this strap.
    enum Requirement: Equatable {
        /// Works without turning anything on. `place` is where to use it, when there is somewhere to go.
        case builtIn(place: Place?)
        /// A switch that must be on. `key` is the `UserDefaults` key the control writes.
        case toggle(key: String, place: Place, control: String)
        /// A picker that must hold `value` under `key`.
        case choice(key: String, value: String, place: Place, control: String)
        /// Not available on this strap; `reason` says why in plain words.
        case unavailable(reason: String)

        var place: Place? {
            switch self {
            case .builtIn(let place): return place
            case .toggle(_, let place, _), .choice(_, _, let place, _): return place
            case .unavailable: return nil
            }
        }
    }

    /// Where a goal stands right now.
    enum Status: Equatable {
        case on
        case off
        case builtIn
        case unavailable
    }

    struct Item: Identifiable, Equatable {
        let id: String
        /// What the wearer wants, in their words.
        let goal: String
        /// What turning it on gets them.
        let gain: String
        let requirement: Requirement
        /// The trade-off, when there is one worth knowing before switching it on.
        let cost: String?
    }

    // MARK: - The mapping

    /// Every goal for `family`, most commonly wanted first.
    ///
    /// `includesAppleHealth` is false on macOS, which has no HealthKit, so the Health-dependent goal is
    /// left out rather than shown as something the wearer cannot do.
    static func items(for family: Family, includesAppleHealth: Bool) -> [Item] {
        var out: [Item] = []

        out.append(Item(
            id: "alarm",
            goal: String(localized: "My band buzzes to wake me"),
            gain: String(localized: "A silent wrist alarm from the strap itself, even if NOOP is closed."),
            requirement: family == .whoop5
                ? .toggle(key: PuffinExperiment.defaultsKey, place: .testCentre, control: String(localized: "Protocol probes"))
                : .builtIn(place: .alarms),
            cost: family == .whoop5
                ? String(localized: "On 5.0 / MG this switch also sends experimental protocol queries to the strap when it connects. Then set the alarm itself in More › Alarms.")
                : nil))

        out.append(Item(
            id: "overnightHrv",
            goal: String(localized: "Better overnight HRV and Charge"),
            gain: String(localized: "Keeps the beat-to-beat stream running while you sleep, instead of only the sparser history the strap stores."),
            requirement: .toggle(key: PuffinExperiment.keepRealtimeForDataKey, place: .settings,
                                 control: String(localized: "Continuous HRV capture")),
            cost: String(localized: "The biggest drain on the strap's battery. Keep \"Overnight only\" on to roughly halve it.")))

        out.append(Item(
            id: "effortRecipe",
            goal: String(localized: "Lifting and intervals count in Effort"),
            gain: String(localized: "Scores effort at every intensity, so strength sets and stop-start sports stop reading near zero."),
            requirement: .toggle(key: PuffinExperiment.banisterEffortKey, place: .settings,
                                 control: String(localized: "Effort: exponential intensity scale")),
            cost: String(localized: "Walks and commutes read higher too, and past days are re-scored.")))

        out.append(Item(
            id: "effortScale",
            goal: String(localized: "Effort on the familiar 0–21 scale"),
            gain: String(localized: "Shows Effort on WHOOP's Day Strain axis. Display only: the score itself does not change."),
            requirement: .choice(key: UnitPrefs.effortScaleKey, value: EffortScale.whoop.rawValue, place: .settings,
                                 control: String(localized: "Effort scale")),
            cost: nil))

        out.append(Item(
            id: "workoutSuggestions",
            goal: String(localized: "Catch workouts I did without a watch"),
            gain: String(localized: "After a sync, NOOP offers to save a stretch of raised heart rate that looks like exercise."),
            requirement: .toggle(key: PuffinExperiment.autoDetectWorkoutsKey, place: .settings,
                                 control: String(localized: "Auto-detect workouts")),
            cost: String(localized: "Sessions another app already logged, such as an Apple Watch workout, are never suggested again.")))

        if includesAppleHealth {
            out.append(Item(
                id: "healthWater",
                goal: String(localized: "Water logged in other apps"),
                gain: String(localized: "Brings in water you log elsewhere, through Apple Health."),
                requirement: .toggle(key: HydrationStore.enabledKey, place: .settings,
                                     control: String(localized: "Hydration tracking")),
                cost: String(localized: "Also needs Apple Health connected, with Water allowed.")))
        }

        if family == .whoop5 {
            out.append(Item(
                id: "broadcastHr",
                goal: String(localized: "Use my band with Garmin, Zwift or gym kit"),
                gain: String(localized: "The strap advertises your heart rate so other equipment can read it directly."),
                requirement: .toggle(key: PuffinExperiment.broadcastHrKey, place: .testCentre,
                                     control: String(localized: "Broadcast heart rate from the strap")),
                cost: String(localized: "Keeps the strap's radio on and drains its battery faster. Turn it off when you are not using it.")))
        }

        out.append(Item(
            id: "bloodOxygen",
            goal: String(localized: "Blood oxygen"),
            gain: String(localized: "An overnight SpO₂ reading."),
            requirement: family == .whoop5
                ? .unavailable(reason: String(localized: "Not available on 5.0 / MG yet: the reading has not been validated, so NOOP does not show one."))
                : .builtIn(place: nil),
            cost: family == .whoop5 ? nil
                : String(localized: "Calculated automatically; a night with too few readings shows none.")))

        return out
    }

    // MARK: - Status

    /// Where `item` stands, read from `defaults`. A missing key reads as the control's default, which is
    /// off for every switch listed here.
    static func status(of item: Item, defaults: UserDefaults = .standard) -> Status {
        switch item.requirement {
        case .builtIn:
            return .builtIn
        case .unavailable:
            return .unavailable
        case .toggle(let key, _, _):
            return defaults.bool(forKey: key) ? .on : .off
        case .choice(let key, let value, _, _):
            return defaults.string(forKey: key) == value ? .on : .off
        }
    }

    /// How many goals that CAN be switched on currently are, out of how many can be. Built-in and
    /// unavailable goals are excluded from both counts: there is nothing for the wearer to do about them.
    static func progress(_ items: [Item], defaults: UserDefaults = .standard) -> (on: Int, of: Int) {
        let switchable = items.filter {
            switch $0.requirement {
            case .toggle, .choice: return true
            case .builtIn, .unavailable: return false
            }
        }
        let on = switchable.filter { status(of: $0, defaults: defaults) == .on }.count
        return (on, switchable.count)
    }
}

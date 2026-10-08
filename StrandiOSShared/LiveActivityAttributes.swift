#if os(iOS)
import Foundation
import ActivityKit

/// Live Activity attributes for an active live-HR / workout session. Shared between the app (which
/// starts/updates the activity) and the widget extension (which renders it on the Lock Screen and in
/// the Dynamic Island).
public struct NOOPActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var bpm: Int?
        public var recovery: Int?
        public var bonded: Bool
        // Effort / strain on NOOP's 0–100 axis (#446) — one more stat in the Dynamic Island expanded
        // region. OPTIONAL with a nil default so an activity started by an older build still decodes.
        public var effort: Int?
        // A workout started in the app, so the banner can name it and count its time. All OPTIONAL with nil /
        // false defaults, so an activity started by an older build still decodes and draws the plain live-HR
        // banner. `workoutStart` is when the session began: the banner counts up from it by itself
        // (`Text(_:style: .timer)`), so no per-second push is needed for the clock.
        public var workoutSport: String?
        public var workoutStart: Date?
        public var workoutPaused: Bool
        /// The session's own Effort (0-100), not the day's.
        public var workoutEffort: Int?

        public init(bpm: Int?, recovery: Int?, bonded: Bool, effort: Int? = nil,
                    workoutSport: String? = nil, workoutStart: Date? = nil, workoutPaused: Bool = false,
                    workoutEffort: Int? = nil) {
            self.bpm = bpm
            self.recovery = recovery
            self.bonded = bonded
            self.effort = effort
            self.workoutSport = workoutSport
            self.workoutStart = workoutStart
            self.workoutPaused = workoutPaused
            self.workoutEffort = workoutEffort
        }
    }

    /// Static title shown for the session.
    public var title: String

    public init(title: String = "Live HR") {
        self.title = title
    }
}
#endif

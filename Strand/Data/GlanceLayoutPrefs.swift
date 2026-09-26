import Foundation

/// Glance (#2463): an opt-in layout for Today, organised the way a glance reads. The three score rings
/// share one card with the day's synthesis and Effort target; below them come the day's stress, a Health
/// Monitor grid of vitals, training load and a timeline of the day. Every ring and tile opens the data
/// behind it.
///
/// Presentation only. It chooses what Today renders and where a tap goes; it computes no figure of its
/// own, so a number shown in Glance is the same resolver's output the classic layout shows.
enum GlanceLayoutPrefs {
    /// `@AppStorage` key for the toggle. Default OFF: the classic Today is unchanged unless a wearer opts
    /// in.
    static let enabledKey = "today.glanceLayout"

    /// `@AppStorage` key for Glance's experimental card, the Energy estimate (`EnergyEstimate`). Default
    /// OFF; the card is labelled experimental when shown.
    static let experimentalKey = "today.glanceExperimental"
}

import SwiftUI
import StrandDesign

// Glance's strap battery (#2463): the charge and when the strap is predicted to run out. The prediction is
// `LiveState.batteryEstimate` (BatteryEstimator over the banked charge samples), the same one the header
// battery button and the Data Sources row read; this only turns its hours remaining into a date.

/// The "~4 days left" wording shared by every surface that states the strap's runtime, so two of them can
/// never round the same hours differently: under 48 h in hours, otherwise in whole days.
enum BatteryRuntimeText {
    static func remaining(hours: Double) -> String? {
        guard hours.isFinite, hours > 0 else { return nil }
        if hours < 48 { return String(localized: "~\(Int(hours.rounded()))h left") }
        let days = Int((hours / 24).rounded())
        return days == 1 ? String(localized: "~1 day left") : String(localized: "~\(days) days left")
    }

    /// When the strap is predicted to die, as "Thu 9 Oct, 22:00", in the app's language.
    static func dieDate(hours: Double, from now: Date) -> String {
        let f = DateFormatter()
        f.locale = AppLanguage.activeLocale
        f.setLocalizedDateFormatFromTemplate("EEEdMMMHmm")
        return f.string(from: now.addingTimeInterval(hours * 3600))
    }
}

/// The strap's charge and predicted empty time. Shown only for a connected WHOOP, like the other strap
/// battery readouts (#2208); says "Charging" instead of a prediction while it charges.
struct GlanceBatteryCard: View {
    @EnvironmentObject private var live: LiveState

    var body: some View {
        if live.connected, live.activeIsWhoop, let pct = live.batteryPct {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                HStack(spacing: NoopMetrics.space2) {
                    Image(systemName: live.charging == true ? "battery.100.bolt" : "battery.50")
                        .foregroundStyle(StrandPalette.statusPositive)
                    Text("Strap battery").font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                    Spacer()
                    Text(verbatim: "\(Int(pct.rounded()))%")
                        .font(StrandFont.number(22))
                        .foregroundStyle(StrandPalette.textPrimary)
                }
                ProgressView(value: min(max(pct, 0), 100), total: 100)
                    .tint(pct < 20 ? StrandPalette.statusWarning : StrandPalette.statusPositive)
                    .accessibilityHidden(true)
                if live.charging == true {
                    Text("Charging").font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                } else if let est = live.batteryEstimate, let left = BatteryRuntimeText.remaining(hours: est.hoursRemaining) {
                    let when = BatteryRuntimeText.dieDate(hours: est.hoursRemaining, from: Date())
                    Text(verbatim: String(localized: "Predicted to run out \(when) (\(left))"))
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("No prediction yet. It needs a few hours of battery readings.")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
            }
            .padding(NoopMetrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NoopPanelSurface(cornerRadius: NoopMetrics.cardRadius))
            .accessibilityElement(children: .combine)
        }
    }
}

import SwiftUI
import StrandDesign
import StrandAnalytics

/// The foot-of-Today entry for a workout NOOP suggested and the wearer has not answered. One line that opens the
/// suggestion's sheet, so closing the sheet (or never seeing the notification) loses nothing. It is the same
/// detector, gate and dismissals the card and the notification use, so the three always agree; it goes away as soon
/// as the suggestion is saved, dismissed, or matched to an Apple Watch workout.
struct PendingWorkoutRow: View {
    @EnvironmentObject var repo: Repository
    @EnvironmentObject var router: NavRouter
    @AppStorage(PuffinExperiment.autoDetectWorkoutsKey) private var autoDetectEnabled = false
    @State private var candidate: DetectedWorkout?

    var body: some View {
        Group {
            if autoDetectEnabled, let w = candidate {
                Button { router.openWorkoutSuggestion() } label: {
                    HStack(spacing: NoopMetrics.space3) {
                        Image(systemName: "figure.run")
                            .font(.system(size: 18))
                            .foregroundStyle(StrandPalette.accent)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("A workout is waiting to be saved")
                                .font(StrandFont.subhead.weight(.semibold))
                                .foregroundStyle(StrandPalette.textPrimary)
                            Text(verbatim: Self.summary(w))
                                .font(StrandFont.caption)
                                .foregroundStyle(StrandPalette.textSecondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(StrandPalette.textTertiary)
                    }
                    .padding(NoopMetrics.cardPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(NoopPanelSurface(cornerRadius: NoopMetrics.cardRadius))
                    .contentShape(Rectangle())
                }
                .buttonStyle(LiquidPressStyle())
                .accessibilityElement(children: .combine)
            }
        }
        .task(id: Key(seq: repo.refreshSeq, answered: repo.suggestionRevision, enabled: autoDetectEnabled)) {
            guard autoDetectEnabled else { candidate = nil; return }
            candidate = await repo.autoDetectCandidate()
        }
    }

    private struct Key: Equatable { let seq: Int; let answered: Int; let enabled: Bool }

    /// "08:11-09:31 · 79 min".
    private static func summary(_ w: DetectedWorkout) -> String {
        let f = AppClock.hourMinuteFormatter()
        let from = f.string(from: Date(timeIntervalSince1970: TimeInterval(w.startSec)))
        let to = f.string(from: Date(timeIntervalSince1970: TimeInterval(w.endSec)))
        return "\(from)-\(to) · \(w.durationMin) min"
    }
}

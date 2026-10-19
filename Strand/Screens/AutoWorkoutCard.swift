import SwiftUI
import StrandDesign
import StrandAnalytics

// MARK: - Auto-detected workout prompt (Today screen)
//
// A single, dismissible Today card that appears ONLY when the opt-in "Auto-detect workouts"
// toggle is on and `Repository.autoDetectCandidate()` finds a recent sustained-elevated HR
// window that isn't already saved and wasn't previously dismissed.
//
// It only ever SUGGESTS: tapping Save creates a manual-style "Workout" for the window (via the
// same manual-save path the edit sheet uses); the X dismisses it durably so it never re-prompts.
// Nothing is created automatically. Design-Reset compliant — a flat NoopCard using NoopMetrics /
// StrandPalette / StrandFont, no gold, matching the other Today cards.

struct AutoWorkoutCard: View {

    @EnvironmentObject var repo: Repository

    /// On the notification's own sheet: never renders nothing. It says it is looking, then shows the suggestion or
    /// the reason there is none.
    var alwaysShow = false
    @State private var loading = true

    /// Whether the toggle is on. Read here too so the card disappears the instant it's switched off.
    @AppStorage(PuffinExperiment.autoDetectWorkoutsKey) private var autoDetectEnabled = false

    /// The current suggestion, loaded in `.task`. nil → nothing to show.
    @State private var candidate: DetectedWorkout?
    /// Hide immediately on Save/X without waiting for the next reload (avoids a flash of the old card).
    @State private var handledThisSession = false
    /// Why the stretch the last notification named has no card, when it has none (see `reloadMissingNote`).
    @State private var missingNote: String?
    /// Guards the Save button while the write is in flight.
    @State private var saving = false
    /// What the wearer saves it as; remembered, so a regular lifter is not asked every time.
    @AppStorage("autoWorkout.lastSport") private var sport = "Workout"

    var body: some View {
        Group {
            if autoDetectEnabled, !handledThisSession, let w = candidate {
                card(for: w)
            } else if alwaysShow, loading {
                HStack(spacing: 8) { ProgressView(); Text("Looking for the workout…").font(StrandFont.footnote) }
                    .foregroundStyle(StrandPalette.textSecondary)
            } else if autoDetectEnabled, let note = missingNote {
                // A notification said there was a suggestion and there is none to show now. Say why, so the
                // tap that brought the wearer here is never answered by an empty page.
                Label { Text(verbatim: note).font(StrandFont.footnote) } icon: { Image(systemName: "info.circle") }
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, NoopMetrics.space2)
            } else if alwaysShow {
                Text(autoDetectEnabled ? "Nothing is waiting to be saved right now." : "Auto-detect workouts is switched off, so there is nothing to suggest.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // Re-scan whenever the data refreshes (a sync bumps refreshSeq) or the toggle flips on.
        .task(id: AutoWorkoutLoadKey(seq: repo.refreshSeq, enabled: autoDetectEnabled)) {
            await reload()
        }
    }

    @ViewBuilder
    private func card(for w: DetectedWorkout) -> some View {
        NoopCard(tint: StrandPalette.accent) {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                HStack(spacing: NoopMetrics.space2) {
                    Image(systemName: "figure.run")
                        .font(.system(size: 18))
                        .foregroundStyle(StrandPalette.accent)
                        .accessibilityHidden(true)
                    Text("Looks like a workout")
                        .font(StrandFont.headline)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Spacer()
                    Button {
                        dismiss(w)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(StrandPalette.textTertiary)
                            .padding(NoopMetrics.space1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss this workout suggestion")
                }

                Text(promptText(w))
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Menu {
                    Picker("What was it?", selection: $sport) {
                        Text("Workout").tag("Workout")
                        ForEach(WorkoutCatalog.all.map(\.name), id: \.self) { Text(verbatim: $0).tag($0) }
                    }
                } label: {
                    Label { Text(verbatim: sport) } icon: { Image(systemName: "chevron.up.chevron.down") }
                        .font(StrandFont.subhead)
                }
                .accessibilityLabel(Text("What was it?"))

                HStack(spacing: NoopMetrics.space3) {
                    Button {
                        save(w)
                    } label: {
                        Label("Save it", systemImage: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(StrandPalette.accent)
                    .disabled(saving)

                    Button("Not a workout") { dismiss(w) }
                        .buttonStyle(.bordered)
                        .disabled(saving)
                    Spacer()
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// "Looks like a workout [yesterday ]around 14:05–14:32 (avg HR 148, 27 min). Save it?"
    /// Three whole-phrase variants (today / yesterday / dated, #719) so translators see complete
    /// sentences rather than a stitched day-label fragment.
    private func promptText(_ w: DetectedWorkout) -> String {
        let startDate = Date(timeIntervalSince1970: TimeInterval(w.startSec))
        let start = Self.timeFmt.string(from: startDate)
        let end = Self.timeFmt.string(from: Date(timeIntervalSince1970: TimeInterval(w.endSec)))
        let cal = Calendar.current
        if cal.isDateInToday(startDate) {
            return String(localized: "Looks like a workout around \(start)-\(end) (avg HR \(w.avgBpm), \(w.durationMin) min). Save it?")
        }
        if cal.isDateInYesterday(startDate) {
            return String(localized: "Looks like a workout yesterday around \(start)-\(end) (avg HR \(w.avgBpm), \(w.durationMin) min). Save it?")
        }
        return String(localized: "Looks like a workout on \(Self.dateFmt.string(from: startDate)) around \(start)-\(end) (avg HR \(w.avgBpm), \(w.durationMin) min). Save it?")
    }

    /// The last notified stretch, if it was within a day and nothing is offering it now: it was saved in the
    /// meantime (the strap's own detection can bank it as a workout after the notification), it was dismissed,
    /// or the heart rate data behind it was revised.
    private func reloadMissingNote() async {
        guard let n = AutoWorkoutNotifier.lastNotified,
              Date().timeIntervalSince1970 - Double(n.end) < 86_400 else { missingNote = nil; return }
        let from = Date(timeIntervalSince1970: TimeInterval(n.start))
        let to = Date(timeIntervalSince1970: TimeInterval(n.end))
        let time = Self.timeFmt
        let range = "\(time.string(from: from))-\(time.string(from: to))"
        if let saved = await repo.workoutRows().first(where: { $0.startTs < n.end && n.start < $0.endTs }) {
            missingNote = String(localized: "The stretch at \(range) is already saved as \(saved.sport) in Workouts.")
        } else {
            missingNote = String(localized: "The stretch at \(range) you were told about is not on offer any more: it was dismissed, or it no longer looks like a workout.")
        }
    }

    private func reload() async {
        defer { loading = false }
        guard autoDetectEnabled else { candidate = nil; missingNote = nil; return }
        let t0 = Date()
        let next = await repo.autoDetectCandidate()
        repo.autoDetectLog?("Workout suggestion card: \(next.map { "candidate \($0.startSec)-\($0.endSec)" } ?? "none") in \(Int(Date().timeIntervalSince(t0) * 1000)) ms")
        if next == nil { await reloadMissingNote() } else { missingNote = nil }
        // A fresh scan resets the session guard so a NEW window can surface after one is handled.
        if next != candidate { handledThisSession = false }
        candidate = next
    }

    private func save(_ w: DetectedWorkout) {
        saving = true
        handledThisSession = true
        Task {
            _ = await repo.saveDetectedWorkout(w, sport: sport)
            await repo.refresh()   // surfaces the new workout + drops it from re-suggestion
            saving = false
        }
    }

    private func dismiss(_ w: DetectedWorkout) {
        repo.dismissDetectedSuggestion(w)
        handledThisSession = true
        candidate = nil
    }

    /// HH:mm in the user's locale/timezone.
    /// #1821: routed through AppClock so the Clock format setting reaches this label. Was a `static
    /// let`, which would have frozen the reader's choice at first use until the app relaunched.
    private static var timeFmt: DateFormatter { AppClock.hourMinuteFormatter() }

    /// Localized medium date ("Jun 23, 2026") for a bout older than yesterday.
    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = AppLanguage.activeLocale
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()
}

/// Reload key: a new sync (seq) or a toggle flip re-runs detection.
private struct AutoWorkoutLoadKey: Equatable {
    let seq: Int
    let enabled: Bool
}

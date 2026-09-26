import SwiftUI
import StrandDesign
import StrandAnalytics

// Glance's experimental card (#2463), shown only when the Glance experimental switch is on: the Energy
// estimate. It says what it is and is never fed into another score.

/// A small "Experimental" tag for a card header.
struct GlanceExperimentalTag: View {
    var body: some View {
        Text("Experimental")
            .font(StrandFont.overline)
            .foregroundStyle(StrandPalette.statusWarning)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().strokeBorder(StrandPalette.statusWarning.opacity(0.6), lineWidth: 1))
    }
}

// MARK: - Energy

/// The Energy estimate as a segmented bar, with what moved it one tap away.
struct GlanceEnergyCard: View {
    /// Nil when there is no scored Charge this morning or no wake time to start from.
    let result: EnergyEstimate.Result?

    @State private var expanded = false
    private static let segments = 30

    var body: some View {
        Button { withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } } label: {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                HStack(spacing: NoopMetrics.space2) {
                    Image(systemName: "bolt.fill").foregroundStyle(StrandPalette.signalYellow)
                    Text("Energy").font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                    GlanceExperimentalTag()
                    Spacer()
                    Text(verbatim: result.map { "\(Int($0.energy.rounded()))%" } ?? "—")
                        .font(StrandFont.number(22))
                        .foregroundStyle(StrandPalette.textPrimary)
                }
                bar
                if let result {
                    if expanded { breakdown(result) }
                } else {
                    Text("Needs a Charge scored this morning and last night's sleep.")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
            }
            .padding(NoopMetrics.cardPadding)
            .background(NoopPanelSurface(cornerRadius: NoopMetrics.cardRadius))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private var bar: some View {
        let lit = Int(((result?.energy ?? 0) / 100 * Double(Self.segments)).rounded())
        return HStack(spacing: 3) {
            ForEach(0..<Self.segments, id: \.self) { i in
                Capsule()
                    .fill(i < lit ? StrandPalette.signalYellow : StrandPalette.surfaceInset)
                    .frame(height: 26)
            }
        }
        .accessibilityHidden(true)
    }

    private func breakdown(_ r: EnergyEstimate.Result) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            row(String(localized: "This morning's Charge"), r.start, sign: "")
            row(String(localized: "Time awake"), -r.awake, sign: nil)
            row(String(localized: "Stress through the day"), -r.stress, sign: nil)
            row(String(localized: "Effort"), -r.effort, sign: nil)
            Text("A rough estimate, not a validated measure: it starts at this morning's Charge and falls with time awake, stressful hours and Effort, rising a little in calm hours.")
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A labelled term; `sign` nil prints the value's own sign.
    private func row(_ label: String, _ v: Double, sign: String?) -> some View {
        HStack {
            Text(verbatim: label).font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
            Spacer()
            Text(verbatim: sign.map { "\($0)\(Int(v.rounded()))" }
                 ?? String(format: "%+d", Int(v.rounded())))
                .font(StrandFont.bodyNumber)
                .foregroundStyle(StrandPalette.textPrimary)
        }
    }
}

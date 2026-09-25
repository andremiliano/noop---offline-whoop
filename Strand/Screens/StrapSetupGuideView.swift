import SwiftUI
import StrandDesign

/// "Set up your strap" (#2463/#2465): what to turn on for what you want to see, per WHOOP generation.
///
/// Goals the wearer can act on are grouped by whether they are on yet, so the page reads as a to-do list
/// rather than a reference table. Each row links to the screen that owns the control instead of toggling
/// it here; see `StrapSetupGuide` for why.
struct StrapSetupGuideView: View {
    @AppStorage("selectedWhoopModel") private var selectedWhoopModelRaw = WhoopModel.whoop4.rawValue
    /// The generation being shown. Starts on the wearer's own and can be switched to preview the other.
    @State private var family: StrapSetupGuide.Family?
    /// Bumped on appear so statuses re-read after returning from a settings screen.
    @State private var refresh = 0

    private var yourFamily: StrapSetupGuide.Family { .forSelectedModel(selectedWhoopModelRaw) }
    private var shown: StrapSetupGuide.Family { family ?? yourFamily }

    private var items: [StrapSetupGuide.Item] {
        #if os(iOS)
        StrapSetupGuide.items(for: shown, includesAppleHealth: true)
        #else
        StrapSetupGuide.items(for: shown, includesAppleHealth: false)
        #endif
    }

    var body: some View {
        let _ = refresh
        let all = items
        let toTurnOn = all.filter { StrapSetupGuide.status(of: $0) == .off }
        let alreadyOn = all.filter { StrapSetupGuide.status(of: $0) == .on }
        let noAction = all.filter {
            let s = StrapSetupGuide.status(of: $0)
            return s == .builtIn || s == .unavailable
        }
        let progress = StrapSetupGuide.progress(all)

        ScreenScaffold(title: "Set up your strap",
                       subtitle: "What to turn on for the data you want. Nothing here changes a setting: each row opens the screen that does.") {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                familyPicker
                progressCard(on: progress.on, of: progress.of)
                if !toTurnOn.isEmpty {
                    group(title: String(localized: "Turn these on for more"), items: toTurnOn)
                }
                if !alreadyOn.isEmpty {
                    group(title: String(localized: "Already on"), items: alreadyOn)
                }
                if !noAction.isEmpty {
                    group(title: String(localized: "Nothing to switch on"), items: noAction)
                }
            }
        }
        .onAppear { refresh &+= 1 }
    }

    // MARK: - Pieces

    private var familyPicker: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            Picker("Strap", selection: Binding(get: { shown }, set: { family = $0 })) {
                ForEach(StrapSetupGuide.Family.allCases) { f in
                    Text(verbatim: f.displayName).tag(f)
                }
            }
            .pickerStyle(.segmented)
            Text(shown == yourFamily
                 ? String(localized: "Showing your strap.")
                 : String(localized: "Previewing a strap you don't have selected."))
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textTertiary)
        }
    }

    private func progressCard(on: Int, of: Int) -> some View {
        NoopCard(tint: StrandPalette.accent) {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                HStack(alignment: .firstTextBaseline, spacing: NoopMetrics.space2) {
                    Text(verbatim: "\(on)")
                        .font(StrandFont.number(34))
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text("of \(of) optional extras switched on")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
                SetupProgressBar(fraction: of > 0 ? Double(on) / Double(of) : 0)
                Text("You don't need all of them. Each one says what it gets you and what it costs.")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func group(title: String, items: [StrapSetupGuide.Item]) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.rowSpacing) {
            Text(verbatim: title.uppercased()).strandOverline()
            ForEach(items) { item in
                StrapSetupRow(item: item, status: StrapSetupGuide.status(of: item))
            }
        }
    }
}

/// One goal: what you want, what it gets you, where the switch is, and what it costs.
private struct StrapSetupRow: View {
    let item: StrapSetupGuide.Item
    let status: StrapSetupGuide.Status

    var body: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                HStack(alignment: .firstTextBaseline, spacing: NoopMetrics.space2) {
                    Text(verbatim: item.goal)
                        .font(StrandFont.headline)
                        .foregroundStyle(StrandPalette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: NoopMetrics.space2)
                    statusPill
                }
                Text(verbatim: item.gain)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let cost = item.cost {
                    HStack(alignment: .firstTextBaseline, spacing: NoopMetrics.space2) {
                        Image(systemName: "exclamationmark.circle")
                            .foregroundStyle(StrandPalette.statusWarning)
                            .accessibilityHidden(true)
                        Text(verbatim: cost)
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                footer
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var statusPill: some View {
        switch status {
        case .on:          StatePill("On", tone: .positive)
        case .off:         StatePill("Off", tone: .neutral, showsDot: false)
        case .builtIn:     StatePill("Built in", tone: .accent, showsDot: false)
        case .unavailable: StatePill("Not yet", tone: .warning, showsDot: false)
        }
    }

    /// Where the control lives, as a link to that screen. An unavailable goal says why instead.
    @ViewBuilder private var footer: some View {
        switch item.requirement {
        case .unavailable(let reason):
            Text(verbatim: reason)
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        case .toggle(_, let place, let control), .choice(_, _, let place, let control):
            link(to: place, label: "\(place.title) › \(control)")
        case .builtIn(let place):
            if let place { link(to: place, label: place.title) }
        }
    }

    /// A closure-destination link, not a `TabRoute` value: this is a deeper hop, and the guide is also
    /// reachable from Settings, whose stack registers no `TabRoute` destinations.
    private func link(to place: StrapSetupGuide.Place, label: String) -> some View {
        NavigationLink {
            Self.destination(for: place)
        } label: {
            HStack(spacing: NoopMetrics.space2) {
                Text(verbatim: label)
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.accent)
                    .multilineTextAlignment(.leading)
                Image(systemName: "chevron.right")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.accent)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Opens the screen with this setting"))
    }

    /// The screen that owns a control: the same views More pushes for these entries.
    @ViewBuilder static func destination(for place: StrapSetupGuide.Place) -> some View {
        switch place {
        case .settings:   SettingsView()
        case .testCentre: TestCentreView()
        case .alarms:     SmartAlarmView()
        }
    }
}

/// A thin filled track for the "n of m switched on" summary.
private struct SetupProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(StrandPalette.surfaceInset)
                Capsule().fill(StrandPalette.accent)
                    .frame(width: max(0, min(1, fraction)) * geo.size.width)
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

/// The Today entry to the guide in Simple view: the wearer's own strap, how much is on, and the first
/// things worth turning on. Taps through to `StrapSetupGuideView`.
struct StrapSetupSummaryCard: View {
    @AppStorage("selectedWhoopModel") private var selectedWhoopModelRaw = WhoopModel.whoop4.rawValue

    var body: some View {
        let family = StrapSetupGuide.Family.forSelectedModel(selectedWhoopModelRaw)
        #if os(iOS)
        let items = StrapSetupGuide.items(for: family, includesAppleHealth: true)
        #else
        let items = StrapSetupGuide.items(for: family, includesAppleHealth: false)
        #endif
        let progress = StrapSetupGuide.progress(items)
        let next = items.filter { StrapSetupGuide.status(of: $0) == .off }.prefix(2)

        NavigationLink(value: TabRoute.strapSetupGuide) {
            NoopCard {
                VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Get more from your \(family.displayName)")
                            .font(StrandFont.headline)
                            .foregroundStyle(StrandPalette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: NoopMetrics.space2)
                        Image(systemName: "chevron.right")
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textTertiary)
                            .accessibilityHidden(true)
                    }
                    Text("\(progress.on) of \(progress.of) optional extras switched on")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                    SetupProgressBar(fraction: progress.of > 0 ? Double(progress.on) / Double(progress.of) : 0)
                    ForEach(Array(next)) { item in
                        HStack(alignment: .firstTextBaseline, spacing: NoopMetrics.space2) {
                            Image(systemName: "circle")
                                .font(StrandFont.caption)
                                .foregroundStyle(StrandPalette.textTertiary)
                                .accessibilityHidden(true)
                            Text(verbatim: item.goal)
                                .font(StrandFont.caption)
                                .foregroundStyle(StrandPalette.textSecondary)
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

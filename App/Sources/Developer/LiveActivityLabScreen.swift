import DesignSystem
import LiveActivity
import Model
import SwiftUI

/// Every Live Activity presentation, drawn from `LiveActivitySamples` with the LiveActivity
/// module's own views, so the snapshot CI exports (`lab.liveactivity`) is what the widget
/// extension draws (docs/decisions/0001-live-activity-views-in-package.md). The island, the Lock
/// Screen's wallpaper and StandBy's black around the views are stand-ins (`ActivityFrames.swift`).
///
/// One section per presentation; each sample is a row naming it, then the presentation on what
/// the system would draw behind it. The matrix at the end puts a solo session in every state side
/// by side, each presentation drawn small, so one screenshot compares them all.
struct LiveActivityLabScreen: View {
    /// The page's parts, in order. Each is also a snapshot route, `lab.liveactivity.<part>`, for
    /// when the whole page is taller than one screenshot.
    enum Panel: String, CaseIterable, Identifiable {
        case states
        case lockScreen = "lockscreen"
        case island
        case standBy = "standby"
        case alwaysOn = "alwayson"
        case watch
        case largest
        /// You alone in each state: the compact island, the minimal and a small Lock Screen card.
        case matrix
        /// The matrix's expanded islands, which don't fit on the same screen.
        case matrixExpanded = "matrix.expanded"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .states: "States"
            case .lockScreen: "Lock Screen"
            case .island: "Dynamic Island"
            case .standBy: "StandBy"
            case .alwaysOn: "Always-On"
            case .watch: "Apple Watch"
            case .largest: "Longest names"
            case .matrix: "Matrix"
            case .matrixExpanded: "Matrix, expanded"
            }
        }
    }

    private let panels: [Panel]
    /// The instant the samples' timers count from.
    @State private var now: Date

    init(now: Date = Date(), panels: [Panel] = Panel.allCases) {
        self.panels = panels
        _now = State(initialValue: now)
    }

    var body: some View {
        let samples = LabSamples(now: now)
        List {
            ForEach(panels) { panel in
                Section(panel.title) {
                    PanelRows(panel: panel, samples: samples)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Live Activity Lab")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                // The samples' timers run from when the screen opened; this starts them again.
                Button("Restart timers", systemImage: "arrow.counterclockwise") {
                    now = Date()
                }
            }
        }
    }
}

/// The samples the Lab draws, all from one instant.
private struct LabSamples {
    let squad: LiveActivitySample
    let squadOfFour: LiveActivitySample
    let solo: LiveActivitySample
    let largest: LiveActivitySample
    let states: [LiveActivityPresentation.Member]
    /// You alone, once in each state.
    let soloStates: [StateSample]

    init(now: Date) {
        squad = LiveActivitySamples.squadOfSix(now: now)
        squadOfFour = LiveActivitySamples.squadOfFour(now: now)
        solo = LiveActivitySamples.solo(now: now)
        largest = LiveActivitySamples.largest(now: now)
        let soloStates = MemberState.allCases.map { state in
            StateSample(state: state, sample: LiveActivitySamples.solo(now: now, me: state))
        }
        self.soloStates = soloStates
        states = soloStates.compactMap { $0.sample.presentation.primary }
    }

    /// What a sample's row says: "Squad", "Squad of 4", "Solo".
    func name(of sample: LiveActivitySample) -> String {
        switch sample.id {
        case squadOfFour.id: "Squad of 4"
        case solo.id: "Solo"
        default: "Squad"
        }
    }
}

/// You alone in one state.
private struct StateSample: Identifiable {
    let state: MemberState
    let sample: LiveActivitySample

    var id: String { sample.id }

    /// What its row says: the state's name, "On a break".
    var name: String { LiveActivityPresentation.tone(for: state).title }
}

/// One panel's rows. A list flattens them, so each `LabItem` here becomes two rows.
private struct PanelRows: View {
    let panel: LiveActivityLabScreen.Panel
    let samples: LabSamples

    var body: some View {
        switch panel {
        case .states:
            Text("Lock Screen")
            StateBadges(members: samples.states, size: 34)
                .padding(.vertical, LKSpacing.m)
                .background(
                    .regularMaterial,
                    in: RoundedRectangle(cornerRadius: ActivityFrameMetrics.lockScreenCornerRadius, style: .continuous)
                )
                .activityStageRow(.wallpaper)
            Text("Dynamic Island")
            StateBadges(members: samples.states, size: 22)
                .environment(\.colorScheme, .dark)
                .activityStageRow(.black)
        case .lockScreen:
            ForEach([samples.squad, samples.squadOfFour, samples.solo]) { sample in
                LabItem(samples.name(of: sample), on: .wallpaper) {
                    LockScreenPreview(sample)
                }
            }
        case .island:
            ForEach([samples.squad, samples.squadOfFour, samples.solo]) { sample in
                LabItem(samples.name(of: sample), note: "Compact, minimal", on: .wallpaper) {
                    HStack(spacing: LKSpacing.m) {
                        CompactIslandPreview(sample)
                        MinimalIslandPreview(sample)
                    }
                }
            }
            ForEach([samples.squad, samples.solo]) { sample in
                LabItem(samples.name(of: sample), note: "Expanded", on: .wallpaper) {
                    ExpandedIslandPreview(sample)
                }
            }
        case .standBy:
            ForEach([samples.squad, samples.solo]) { sample in
                LabItem(samples.name(of: sample), on: .black) {
                    LockScreenPreview(sample, layout: .standBy)
                }
            }
        case .alwaysOn:
            ForEach([samples.squad, samples.solo]) { sample in
                LabItem(samples.name(of: sample), on: .dimmedWallpaper) {
                    LockScreenPreview(sample, isLuminanceReduced: true)
                }
            }
        case .watch:
            ForEach([samples.squad, samples.solo]) { sample in
                LabItem(samples.name(of: sample), on: .black) {
                    LockScreenPreview(sample, layout: .smartStack)
                }
            }
        case .largest:
            LabItem("Squad", note: "Lock Screen", on: .wallpaper) {
                LockScreenPreview(samples.largest)
            }
            LabItem("Squad", note: "Dynamic Island", on: .wallpaper) {
                VStack(spacing: LKSpacing.m) {
                    HStack(spacing: LKSpacing.m) {
                        CompactIslandPreview(samples.largest)
                        MinimalIslandPreview(samples.largest)
                    }
                    ExpandedIslandPreview(samples.largest)
                }
            }
        case .matrix:
            StateMatrix(rows: samples.soloStates) { sample in
                VStack(alignment: .leading, spacing: LKSpacing.s) {
                    HStack(spacing: LKSpacing.s) {
                        CompactIslandPreview(sample)
                        MinimalIslandPreview(sample)
                    }
                    MiniaturePreview(scale: StateMatrixMetrics.lockScreenScale) {
                        LockScreenPreview(sample)
                            .frame(width: ActivityFrameMetrics.lockScreenWidth)
                    }
                }
            }
        case .matrixExpanded:
            StateMatrix(rows: samples.soloStates) { sample in
                MiniaturePreview(scale: StateMatrixMetrics.expandedScale) {
                    ExpandedIslandPreview(sample)
                        .frame(width: ActivityFrameMetrics.expandedWidth)
                }
            }
        }
    }
}

/// How small the matrix draws the presentations that don't fit at full size. Each part has to
/// fit one iPhone 16 Pro screenshot, about 690 points of list under the navigation bar.
private enum StateMatrixMetrics {
    /// The Lock Screen card under each row's islands: about 223 × 60 for a running session, so
    /// the six rows come to about 680 points.
    static let lockScreenScale: CGFloat = 0.6
    /// The expanded islands, as wide as the column beside the state names allows: about 260
    /// points, and about 520 points for all six.
    static let expandedScale: CGFloat = 0.7
}

/// You alone in each state, one row each: the state's name, then `content` for its sample. The
/// rows share one stage, so all six fit on a screen.
private struct StateMatrix<Content: View>: View {
    let rows: [StateSample]
    @ViewBuilder let content: (LiveActivitySample) -> Content

    var body: some View {
        Grid(alignment: .topLeading, horizontalSpacing: LKSpacing.s, verticalSpacing: LKSpacing.m) {
            ForEach(rows) { row in
                GridRow {
                    StateLabel(row.name)
                    content(row.sample)
                }
            }
        }
        .activityStageRow(.wallpaper)
    }
}

/// A state's name on the stage: on a chip of the Lock Screen card's material, so it reads on the
/// wallpaper in either appearance, and as tall as the compact island, so it lines up beside it.
private struct StateLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(LKFont.caption.weight(.semibold))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, LKSpacing.s)
            .padding(.vertical, LKSpacing.xs)
            .background(.regularMaterial, in: Capsule())
            .frame(height: ActivityFrameMetrics.compactHeight)
    }
}

/// One badge per member state at one size, with the state's name under it.
private struct StateBadges: View {
    let members: [LiveActivityPresentation.Member]
    let size: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // By state: every one of these is you, so they share a member id.
            ForEach(members, id: \.state) { member in
                VStack(spacing: LKSpacing.s) {
                    MemberBadge(member, size: size)
                    Text(member.tone.title)
                        .font(LKFont.caption)
                        .foregroundStyle(LKColor.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, LKSpacing.xs)
    }
}

/// One sample in one presentation: a row naming it, then a stage row with the presentation on
/// `backdrop`.
private struct LabItem<Content: View>: View {
    let name: String
    let note: String?
    let backdrop: ActivityBackdrop
    let content: Content

    init(_ name: String, note: String? = nil, on backdrop: ActivityBackdrop, @ViewBuilder content: () -> Content) {
        self.name = name
        self.note = note
        self.backdrop = backdrop
        self.content = content()
    }

    var body: some View {
        if let note {
            LabeledContent(name, value: note)
        } else {
            Text(name)
        }
        content
            .activityStageRow(backdrop)
    }
}

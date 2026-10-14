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
/// the system would draw behind it.
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

    init(now: Date) {
        squad = LiveActivitySamples.squadOfSix(now: now)
        squadOfFour = LiveActivitySamples.squadOfFour(now: now)
        solo = LiveActivitySamples.solo(now: now)
        largest = LiveActivitySamples.largest(now: now)
        // You alone, once in each state.
        states = MemberState.allCases.compactMap { state in
            LiveActivitySamples.solo(now: now, me: state).presentation.primary
        }
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
        }
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

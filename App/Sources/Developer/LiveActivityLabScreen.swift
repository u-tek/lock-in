import DesignSystem
import LiveActivity
import Model
import SwiftUI

/// Every Live Activity presentation, drawn from `LiveActivitySamples` with the LiveActivity
/// module's own views, so the snapshot CI exports (`lab.liveactivity`) is what the widget
/// extension draws (docs/decisions/0001-live-activity-views-in-package.md).
///
/// M0 shows the squad and solo samples in each presentation; M1 extends it to every presentation
/// × state. The island, the Lock Screen's wallpaper and StandBy's black around the views are
/// stand-ins (`ActivityFrames.swift`).
///
/// An inset-grouped list, one section per presentation. Each sample is two rows: its name and
/// payload size as label and value, then a stage row with the presentation on what the system
/// would draw behind it.
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
            case .states: "Member states"
            case .lockScreen: "Lock Screen"
            case .island: "Dynamic Island"
            case .standBy: "StandBy"
            case .alwaysOn: "Always-On"
            case .watch: "Apple Watch Smart Stack"
            case .largest: "Largest payload"
            }
        }

        var detail: String {
            switch self {
            case .states: "Each state's colour and symbol, on the Lock Screen's card and in the island's black."
            case .lockScreen: "On the system's default background over a stand-in wallpaper. Also the banner on iPhones without the Dynamic Island."
            case .island: "Compact, minimal and expanded. The island is always dark, so it's drawn in the dark appearance here too."
            case .standBy: "Shown at 1×; the system scales it up to fill the screen, always on black."
            case .alwaysOn: "Reduced luminance: outlines, nothing glows. The dimming is a stand-in for the system's."
            case .watch: "The small activity family, on the watch face's black."
            case .largest: "Every limit at its maximum, against the 3,584-byte budget."
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
                Section {
                    PanelRows(panel: panel, samples: samples)
                } header: {
                    Text(panel.title)
                } footer: {
                    Text(panel.detail)
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
}

/// One panel's rows. A list flattens them, so each `LabItem` here becomes two rows.
private struct PanelRows: View {
    let panel: LiveActivityLabScreen.Panel
    let samples: LabSamples

    var body: some View {
        switch panel {
        case .states:
            LabeledContent("Lock Screen", value: "34 pt")
            StateBadges(members: samples.states, size: 34)
                .padding(.vertical, LKSpacing.m)
                .background(
                    .regularMaterial,
                    in: RoundedRectangle(cornerRadius: ActivityFrameMetrics.lockScreenCornerRadius, style: .continuous)
                )
                .activityStageRow(.wallpaper)
            LabeledContent("Dynamic Island", value: "22 pt")
            StateBadges(members: samples.states, size: 22)
                .environment(\.colorScheme, .dark)
                .activityStageRow(.black)
        case .lockScreen:
            ForEach([samples.squad, samples.squadOfFour, samples.solo]) { sample in
                LabItem(sample, on: .wallpaper) {
                    LockScreenPreview(sample)
                }
            }
        case .island:
            ForEach([samples.squad, samples.squadOfFour, samples.solo]) { sample in
                LabItem(sample, note: "Compact and minimal", on: .wallpaper) {
                    HStack(spacing: LKSpacing.m) {
                        CompactIslandPreview(sample)
                        MinimalIslandPreview(sample)
                    }
                }
            }
            ForEach([samples.squad, samples.solo]) { sample in
                LabItem(sample, note: "Expanded", on: .wallpaper) {
                    ExpandedIslandPreview(sample)
                }
            }
        case .standBy:
            ForEach([samples.squad, samples.solo]) { sample in
                LabItem(sample, on: .black) {
                    LockScreenPreview(sample, layout: .standBy)
                }
            }
        case .alwaysOn:
            ForEach([samples.squad, samples.solo]) { sample in
                LabItem(sample, on: .dimmedWallpaper) {
                    LockScreenPreview(sample, isLuminanceReduced: true)
                }
            }
        case .watch:
            ForEach([samples.squad, samples.solo]) { sample in
                LabItem(sample, on: .black) {
                    LockScreenPreview(sample, layout: .smartStack)
                }
            }
        case .largest:
            LabItem(samples.largest, note: "Lock Screen", on: .wallpaper) {
                LockScreenPreview(samples.largest)
            }
            LabItem(samples.largest, note: "Dynamic Island", on: .wallpaper) {
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

/// One sample in one presentation: a row naming it with its payload size, then a stage row with
/// the presentation on `backdrop`.
private struct LabItem<Content: View>: View {
    let sample: LiveActivitySample
    let note: String?
    let backdrop: ActivityBackdrop
    let content: Content

    init(_ sample: LiveActivitySample, note: String? = nil, on backdrop: ActivityBackdrop, @ViewBuilder content: () -> Content) {
        self.sample = sample
        self.note = note
        self.backdrop = backdrop
        self.content = content()
    }

    var body: some View {
        LabeledContent {
            Text(size)
                .monospacedDigit()
        } label: {
            Text(sample.title)
            // A second Text in the label is the row's subtitle.
            if let note {
                Text(note)
            }
        }
        content
            .activityStageRow(backdrop)
    }

    /// "804 bytes": attributes and content-state as compact JSON, against the 3,584-byte budget.
    private var size: String {
        let bytes = sample.attributes.payloadByteCount(for: sample.state)
        return bytes == Int.max ? "Won't encode" : "\(bytes.formatted()) bytes"
    }
}

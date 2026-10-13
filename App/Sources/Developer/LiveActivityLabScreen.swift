import DesignSystem
import LiveActivity
import Model
import SwiftUI

/// Every Live Activity presentation, drawn from `LiveActivitySamples` with the LiveActivity
/// module's own views, so the snapshot CI exports (`lab.liveactivity`) is what the widget
/// extension draws (docs/decisions/0001-live-activity-views-in-package.md).
///
/// M0 shows the squad and solo samples in each presentation; M1 extends it to every presentation
/// × state. The island and the Lock Screen around the views are mock-ups (`ActivityFrames.swift`).
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
        ScrollView {
            VStack(alignment: .leading, spacing: LKSpacing.xxl) {
                ForEach(panels) { panel in
                    PanelView(panel: panel, samples: samples)
                }
            }
            .padding(.horizontal, LKSpacing.gutter)
            .padding(.top, LKSpacing.l)
            .padding(.bottom, LKSpacing.xxxl)
        }
        .lkScreenBackground()
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

private struct PanelView: View {
    let panel: LiveActivityLabScreen.Panel
    let samples: LabSamples

    var body: some View {
        switch panel {
        case .states:
            LabPanel("Member states", detail: "Badges at 34 and 22 pt") {
                StateBadges(members: samples.states)
            }
        case .lockScreen:
            LabPanel("Lock Screen", detail: "Also the banner without an island") {
                ForEach([samples.squad, samples.squadOfFour, samples.solo]) { sample in
                    LabItem(sample) {
                        LockScreenPreview(sample)
                    }
                }
            }
        case .island:
            LabPanel("Dynamic Island", detail: "Compact, minimal, expanded") {
                ForEach([samples.squad, samples.squadOfFour, samples.solo]) { sample in
                    LabItem(sample) {
                        HStack(spacing: LKSpacing.m) {
                            CompactIslandPreview(sample)
                            MinimalIslandPreview(sample)
                        }
                    }
                }
                ForEach([samples.squad, samples.solo]) { sample in
                    LabItem(sample, note: "expanded") {
                        ExpandedIslandPreview(sample)
                    }
                }
            }
        case .standBy:
            LabPanel("StandBy", detail: "Shown here at 1×; the system scales it up") {
                ForEach([samples.squad, samples.solo]) { sample in
                    LabItem(sample) {
                        LockScreenPreview(sample, layout: .standBy)
                    }
                }
            }
        case .alwaysOn:
            LabPanel("Always-On", detail: "Reduced luminance: outlines, nothing glows") {
                ForEach([samples.squad, samples.solo]) { sample in
                    LabItem(sample) {
                        LockScreenPreview(sample, isLuminanceReduced: true)
                    }
                }
            }
        case .watch:
            LabPanel("Apple Watch Smart Stack", detail: "The small activity family") {
                HStack(alignment: .top, spacing: LKSpacing.m) {
                    ForEach([samples.squad, samples.solo]) { sample in
                        LockScreenPreview(sample, layout: .smartStack)
                    }
                }
            }
        case .largest:
            LabPanel("Largest payload", detail: "Every limit at its maximum") {
                LabItem(samples.largest) {
                    LockScreenPreview(samples.largest)
                }
                LabItem(samples.largest, note: "island") {
                    VStack(alignment: .leading, spacing: LKSpacing.m) {
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
}

/// One badge per member state, at the Lock Screen row's size and the island's, on the activity's
/// background.
private struct StateBadges: View {
    let members: [LiveActivityPresentation.Member]

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // By state: every one of these is you, so they share a member id.
            ForEach(members, id: \.state) { member in
                VStack(spacing: LKSpacing.s) {
                    MemberBadge(member, size: 34)
                    MemberBadge(member, size: 22)
                    Text(member.tone.title)
                        .font(LKFont.caption)
                        .foregroundStyle(LKColor.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, LKSpacing.l)
        .padding(.horizontal, LKSpacing.s)
        .frame(maxWidth: ActivityFrameMetrics.lockScreenWidth)
        .background(
            LKColor.liveActivityBackground,
            in: RoundedRectangle(cornerRadius: ActivityFrameMetrics.lockScreenCornerRadius, style: .continuous)
        )
        .lkNightAppearance()
    }
}

/// A titled part of the page.
private struct LabPanel<Content: View>: View {
    let title: String
    let detail: String
    let content: Content

    init(_ title: String, detail: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.detail = detail
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LKSpacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(LKFont.title)
                    .foregroundStyle(LKColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(detail)
                    .font(LKFont.caption)
                    .foregroundStyle(LKColor.textSecondary)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One sample in one presentation, captioned with the sample and its payload size.
private struct LabItem<Content: View>: View {
    let sample: LiveActivitySample
    let note: String?
    let content: Content

    init(_ sample: LiveActivitySample, note: String? = nil, @ViewBuilder content: () -> Content) {
        self.sample = sample
        self.note = note
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LKSpacing.xs) {
            Text(caption)
                .font(LKFont.caption)
                .foregroundStyle(LKColor.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            content
        }
    }

    /// "Squad of 6, one in every state · 1,024 bytes". Attributes and content-state as compact
    /// JSON, against the 3,584-byte budget.
    private var caption: String {
        let bytes = sample.attributes.payloadByteCount(for: sample.state)
        let size = bytes == Int.max ? "won't encode" : "\(bytes.formatted()) bytes"
        return [sample.title, note, size].compactMap { $0 }.joined(separator: " · ")
    }
}

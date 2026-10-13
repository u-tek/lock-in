import ActivityKit
import Core
import DesignSystem
import LiveActivity
import Model
import SwiftUI
import UIKit

/// The M0 spike's phone end (docs/spikes/apns-worker.md): starts a squad Live Activity named
/// "Spike Squad" that takes push updates, and copies what the Push test workflow needs to reach it.
struct APNsSpikeScreen: View {
    @StateObject private var model: APNsSpikeModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    /// The real thing: starts and ends Live Activities.
    init() {
        _model = StateObject(wrappedValue: APNsSpikeModel(controller: AppServices.liveActivities))
    }

    /// A fixed state with no ActivityKit behind it, for snapshots.
    init(snapshot: APNsSpikeModel.Snapshot) {
        _model = StateObject(wrappedValue: APNsSpikeModel(snapshot: snapshot))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LKSpacing.xl) {
                Text("Start a Live Activity here, then send it an update from the deployed Worker. If it changes on the Lock Screen, APNs works from Cloudflare.")
                    .font(LKFont.subheadline)
                    .foregroundStyle(LKColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                status

                if !model.activitiesEnabled {
                    turnedOff
                }

                if let problem = model.problem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(LKFont.subheadline)
                        .foregroundStyle(LKColor.textPrimary)
                        .symbolRenderingMode(.multicolor)
                        .fixedSize(horizontal: false, vertical: true)
                        .lkCard()
                }

                actions

                instructions
            }
            .padding(.horizontal, LKSpacing.gutter)
            .padding(.top, LKSpacing.l)
            .padding(.bottom, LKSpacing.xxxl)
        }
        .lkScreenBackground()
        .navigationTitle("APNs spike")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await model.observeEnablement()
        }
        // A new activity starts a new token stream; the old one ends with its task.
        .task(id: model.session) {
            await model.observeTokens()
        }
        // An end that arrives while the screen is open, not only on a return to the foreground.
        .task(id: model.session) {
            await model.observeState()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.refresh()
            }
        }
    }

    // MARK: - Status

    private var status: some View {
        VStack(alignment: .leading, spacing: LKSpacing.m) {
            StatusRow(label: "Live Activities", value: model.activitiesEnabled ? "On" : "Off")
            StatusRow(label: "APNs environment", value: BuildInfo.describe(model.environment))
            StatusRow(label: "Session", value: model.session?.sid ?? "none yet")
            VStack(alignment: .leading, spacing: LKSpacing.xs) {
                Text("Push token")
                    .font(LKFont.subheadline)
                    .foregroundStyle(LKColor.textSecondary)
                Text(tokenText)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(model.token == nil ? LKColor.textTertiary : LKColor.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .lkCard()
    }

    private var tokenText: String {
        if let token = model.token { return token }
        return model.session == nil ? "Start an activity to get one." : "Waiting for the system to issue it…"
    }

    private var turnedOff: some View {
        VStack(alignment: .leading, spacing: LKSpacing.m) {
            Label("Live Activities are off for Lockin", systemImage: "exclamationmark.circle.fill")
                .font(LKFont.headline)
                .foregroundStyle(LKColor.textPrimary)
            Text("Turn them on in Settings › Lockin › Live Activities, then come back. Nothing can show in the Dynamic Island until then.")
                .font(LKFont.subheadline)
                .foregroundStyle(LKColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            .buttonStyle(.lkSecondary)
        }
        .lkCard()
    }

    // MARK: - Actions

    @ViewBuilder
    private var actions: some View {
        if model.session == nil {
            Button {
                model.start()
            } label: {
                Label("Start a 25-minute activity", systemImage: "play.fill")
            }
            .buttonStyle(.lkPrimary)
            .disabled(!model.activitiesEnabled || model.isBusy)
        } else {
            VStack(spacing: LKSpacing.m) {
                if let blob = model.blob {
                    let copied = model.copiedBlob == blob
                    Button {
                        model.copy(blob)
                    } label: {
                        Label(copied ? Self.copiedTitle : Self.copyTitle, systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.lkPrimary)
                    ShareLink(item: blob) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.lkSecondary)
                } else {
                    HStack(spacing: LKSpacing.s) {
                        ProgressView()
                        Text("Waiting for the push token")
                            .font(LKFont.subheadline)
                            .foregroundStyle(LKColor.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, LKSpacing.s)
                }
                Button {
                    Task { await model.end() }
                } label: {
                    Label("End the activity", systemImage: "stop.fill")
                }
                .buttonStyle(.lkSecondary)
                .disabled(model.isBusy)
            }
        }
    }

    private static let copyTitle = "Copy for the Push test"
    private static let copiedTitle = "Copied"

    // MARK: - Instructions

    private var instructions: some View {
        VStack(alignment: .leading, spacing: LKSpacing.m) {
            LKSectionHeader("How to run it")
            Step(number: 1, text: "Tap Start: it starts the squad \"\(APNsSpikeModel.squadName)\", with just you in it. Wait for the push token, then tap Copy. It copies {\"env\", \"me\", \"sid\", \"token\"} as one line of JSON.")
            Step(number: 2, text: "In the GitHub app, open this repository › Actions › Push test › Run workflow. Paste into the first box (\"Paste what the APNs spike screen copies…\"), pick a scenario and run it.")
            Step(number: 3, text: "Lock the phone and watch the Lock Screen, or stay in the GitHub app and watch the Dynamic Island.")
            Text("TestFlight builds must say production. If iOS closes Lockin in the background, opening it again ends the old activity: start a new one and copy again. After the end scenario, start a new one too.")
                .font(LKFont.caption)
                .foregroundStyle(LKColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct StatusRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: LKSpacing.m) {
            Text(label)
                .font(LKFont.subheadline)
                .foregroundStyle(LKColor.textSecondary)
            Spacer(minLength: LKSpacing.s)
            Text(value)
                .font(LKFont.subheadline.weight(.semibold))
                .foregroundStyle(LKColor.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct Step: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: LKSpacing.m) {
            Text(verbatim: "\(number)")
                .font(LKFont.headline.monospacedDigit())
                .foregroundStyle(LKColor.accentText)
                .frame(width: 18, alignment: .leading)
            Text(text)
                .font(LKFont.subheadline)
                .foregroundStyle(LKColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Model

/// Starts and ends the spike's Live Activity and follows its push token.
///
/// Push tokens are never logged (Core's `Log` rules): this screen shows the token, and the person
/// holding the phone decides where to paste it.
@MainActor
final class APNsSpikeModel: ObservableObject {
    /// The activity this screen follows, by the ids in its attributes.
    struct Session: Hashable, Sendable {
        let sid: String
        let me: String
    }

    /// Everything the screen shows, for a snapshot to set without ActivityKit.
    struct Snapshot: Sendable {
        var activitiesEnabled: Bool
        var environment: APNsEnvironment.Resolution
        var session: Session?
        var token: String?
        var problem: String?

        /// Before Start: Live Activities on, nothing running.
        static var preStart: Snapshot {
            Snapshot(activitiesEnabled: true, environment: APNsEnvironment.currentResolution)
        }
    }

    /// What the Push test workflow's "device" input takes: the body of `POST /admin/push-test`
    /// without a scenario.
    struct DeviceBlob: Codable, Equatable {
        let token: String
        let env: String
        let me: String
        let sid: String
    }

    @Published private(set) var activitiesEnabled = true
    @Published private(set) var session: Session? = nil
    @Published private(set) var token: String? = nil
    @Published private(set) var problem: String? = nil
    @Published private(set) var isBusy = false
    /// The last blob copied, so the button can say so.
    @Published private(set) var copiedBlob: String? = nil

    let environment: APNsEnvironment.Resolution

    /// The spike activity's squad name. Must match `sq` in server/src/demo.ts: the attributes the
    /// Worker counts payload bytes against. Pushes carry no attributes, so this is what the Lock
    /// Screen shows.
    static let squadName = "Spike Squad"

    /// What the screen says when the activity ends without its End button.
    private static let endedProblem = "The activity has ended, by an end push or by the system. Start a new one and copy again."

    /// Nil for a snapshot: then nothing here touches ActivityKit.
    private let controller: LiveActivityController?
    private var activity: LockinActivity?

    init(controller: LiveActivityController) {
        self.controller = controller
        environment = APNsEnvironment.currentResolution
        activitiesEnabled = controller.areActivitiesEnabled
        adoptRunningActivity()
    }

    init(snapshot: Snapshot) {
        controller = nil
        environment = snapshot.environment
        activitiesEnabled = snapshot.activitiesEnabled
        session = snapshot.session
        token = snapshot.token
        problem = snapshot.problem
    }

    /// The request body to paste, once there's a token. Keys sorted, so it reads the same every
    /// time.
    var blob: String? {
        guard let token, let session else { return nil }
        return Self.blob(DeviceBlob(token: token, env: environment.environment.rawValue, me: session.me, sid: session.sid))
    }

    static func blob(_ device: DeviceBlob) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(device) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Actions

    /// Starts a 25-minute squad activity named `squadName` that takes push updates: a session id
    /// made here, this install's member id, and one member, "You". Squad attributes, so the Worker's
    /// made-up squad gets the squad layout on the Lock Screen and "+3" in the compact island;
    /// attributes can't change after the start.
    func start() {
        guard let controller, activity == nil, !isBusy else { return }
        problem = nil
        let me = LocalMember.id()
        let now = Date()
        let attributes = LockinAttributes(sid: ShortID.make(), me: me, sq: Self.squadName)
        let member = LockinAttributes.ContentState.Member(
            id: me,
            name: "You",
            avatar: .default,
            state: .focusing,
            start: now,
            end: now.addingTimeInterval(SessionPreset.twentyFive.duration)
        )
        do {
            // Version 1: the Worker's pushes carry v = Unix seconds, so each one is newer.
            let state = LockinAttributes.ContentState(v: 1, m: [member], p: nil, c: nil)
            let started = try controller.start(attributes: attributes, state: state, now: now)
            adopt(started)
        } catch {
            let reason = LiveActivityError(error)
            if reason == .disabled {
                activitiesEnabled = false
            }
            problem = reason.description
        }
    }

    /// Ends the activity straight away: it leaves the island and the Lock Screen.
    func end() async {
        guard let controller, let activity, !isBusy else { return }
        isBusy = true
        await controller.end(activity, state: nil, dismissal: .immediate)
        forget()
        isBusy = false
    }

    func copy(_ blob: String) {
        UIPasteboard.general.string = blob
        copiedBlob = blob
    }

    // MARK: - Following the system

    /// Whether Live Activities are allowed, as the user changes it in Settings. Runs until the
    /// screen goes away.
    func observeEnablement() async {
        guard let controller else { return }
        for await enabled in controller.enablementUpdates {
            activitiesEnabled = enabled
        }
    }

    /// The activity's push token: the first one and every change. Runs until the screen goes
    /// away or the activity changes.
    func observeTokens() async {
        guard let controller, let activity else { return }
        let sid = activity.attributes.sid
        for await token in controller.pushTokens(of: activity) {
            guard self.activity?.id == activity.id else { return }
            self.token = token
            Log.liveActivity.info("Push token ready for session \(sid, privacy: .public)")
        }
    }

    /// The activity's state: the current one, then each change. Notices an end (an `end` push, a
    /// swipe-away, the system) while the screen is open. Runs until the activity ends, the screen
    /// goes away or the activity changes.
    func observeState() async {
        guard controller != nil, let activity else { return }
        if noteState(activity.activityState, of: activity) { return }
        for await state in activity.activityStateUpdates {
            if noteState(state, of: activity) { return }
        }
    }

    /// Back in the foreground: Settings may have changed, and a push may have ended the activity.
    func refresh() {
        guard let controller else { return }
        activitiesEnabled = controller.areActivitiesEnabled
        if let activity {
            _ = noteState(activity.activityState, of: activity)
        } else {
            adoptRunningActivity()
        }
    }

    // MARK: - Helpers

    /// Follows an activity started earlier in this launch, so leaving the screen and coming back
    /// (or tapping the activity) doesn't lose it. Activities from earlier launches are being
    /// ended, so they're skipped.
    private func adoptRunningActivity() {
        guard let controller, activity == nil else { return }
        let orphans = AppServices.orphanIDs
        guard let running = controller.activities.first(where: { !orphans.contains($0.id) }) else { return }
        adopt(running)
    }

    private func adopt(_ activity: LockinActivity) {
        self.activity = activity
        session = Session(sid: activity.attributes.sid, me: activity.attributes.me)
        token = activity.pushToken.map(PushToken.hex)
        copiedBlob = nil
    }

    /// Forgets `activity` once `state` says it has ended, and says so. Returns true when there's
    /// nothing more to follow: it ended, or the screen has moved on to another activity.
    private func noteState(_ state: ActivityState, of activity: LockinActivity) -> Bool {
        guard self.activity?.id == activity.id else { return true }
        guard state == .ended || state == .dismissed else { return false }
        // Our own End button: end() is already forgetting it, and it isn't a problem.
        if isBusy { return true }
        forget()
        problem = Self.endedProblem
        return true
    }

    private func forget() {
        activity = nil
        session = nil
        token = nil
        copiedBlob = nil
    }
}

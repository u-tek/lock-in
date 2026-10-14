import Core
import LiveActivity
import Model
import SwiftUI
import UIKit

/// A scripted squad session for CI to film in the simulator's real Dynamic Island and Lock Screen
/// (`scripts/island-demo.sh`, `UITests/IslandDemoTests`). Launch argument `-LKIslandDemo YES`, and
/// only in builds with the developer tools (`LK_DEVELOPER_TOOLS`), so it never ships.
///
/// It starts a real Live Activity for "Library Goblins" (you, Noor and Kai locked in), then updates
/// it the way the room's pushes would: Mateo joins after 10 seconds and Noor cheers you at 20. Both
/// land inside the half-minute iOS gives an app in the background. The app keeps running in the background meanwhile, so the updates land
/// while the island and the Lock Screen are on show.
@MainActor
final class IslandDemo: ObservableObject {
    static let shared = IslandDemo()

    /// Set once the activity is up: the test waits for its marker (`lk.island.started`).
    @Published private(set) var hasStarted = false
    /// Why the activity couldn't start, for the test to report (`lk.island.failed`).
    @Published private(set) var failure: String?

    static var isRequested: Bool {
        AppConfiguration.main.developerToolsEnabled && UserDefaults.standard.bool(forKey: "LKIslandDemo")
    }

    private static let joinsAt: TimeInterval = 10
    private static let cheersAt: TimeInterval = 20
    /// How long the app asks to keep running in the background: iOS allows about 30 seconds.
    private static let lasts: TimeInterval = 28

    private static let me = "Av4Nq8sT2b"
    private static let noor = "Nr2Kx7pQ1m"

    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    /// Before any screen exists: the demo skips onboarding.
    static func prepare() {
        guard isRequested else { return }
        OnboardingState.markComplete()
    }

    func run(controller: LiveActivityController) async {
        guard Self.isRequested, !hasStarted else { return }
        let start = Date()
        let attributes = LockinAttributes(sid: "dEm0Isl4nd", me: Self.me, sq: "Library Goblins")
        let activity: LockinActivity
        do {
            // CI's simulator build is unsigned, so it has no push entitlement: a local activity,
            // updated below the way the room's pushes would.
            activity = try controller.start(
                attributes: attributes,
                state: Self.state(v: 1, at: start, mateo: false, cheer: nil),
                takesPushes: false
            )
        } catch {
            Log.liveActivity.error("Island demo couldn't start its activity")
            failure = String(describing: error)
            return
        }
        hasStarted = true
        // Called on the main thread when the time runs out.
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Island demo") {
            MainActor.assumeIsolated {
                IslandDemo.shared.endBackgroundTask()
            }
        }

        await pause(until: start.addingTimeInterval(Self.joinsAt))
        await controller.update(activity, state: Self.state(v: 2, at: start, mateo: true, cheer: nil))

        await pause(until: start.addingTimeInterval(Self.cheersAt))
        let cheer = LockinAttributes.ContentState.Cheer(f: Self.noor, t: Self.me, k: 1, at: Date().timeIntervalSince1970)
        await controller.update(activity, state: Self.state(v: 3, at: start, mateo: true, cheer: cheer))

        await pause(until: start.addingTimeInterval(Self.lasts))
        endBackgroundTask()
    }

    private func pause(until date: Date) async {
        let wait = date.timeIntervalSinceNow
        guard wait > 0 else { return }
        try? await Task.sleep(for: .seconds(wait))
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    /// The squad at `start`: you 25 minutes, Noor 50 minutes started four minutes ago, Kai near the
    /// end of 25; Mateo's 50 minutes from when he joins. A happy teen sprout.
    private static func state(
        v: Int,
        at start: Date,
        mateo: Bool,
        cheer: LockinAttributes.ContentState.Cheer?
    ) -> LockinAttributes.ContentState {
        let t = start.timeIntervalSince1970
        let focusing = MemberState.focusing.rawValue
        typealias Member = LockinAttributes.ContentState.Member
        var members = [
            Member(i: me, n: "Ava", a: "b3.c7.e2.h4", s: focusing, b: t, e: t + 25 * 60),
            Member(i: noor, n: "Noor", a: "b1.c2.e5.h0", s: focusing, b: t - 240, e: t + 46 * 60),
            Member(i: "Ka9Lm3Vx0c", n: "Kai", a: "b2.c4.e1.h2", s: focusing, b: t - 18 * 60, e: t + 7 * 60),
        ]
        if mateo {
            let joined = t + joinsAt
            members.append(Member(i: "Mt5Rw1Zy8d", n: "Mateo", a: "b4.c1.e3.h1", s: focusing, b: joined, e: joined + 50 * 60))
        }
        return LockinAttributes.ContentState(
            v: v,
            m: members,
            p: LockinAttributes.ContentState.Pet(k: "sprout.2", md: 3, x: 0.64),
            c: cheer
        )
    }
}

/// An invisible element the UI test waits for before it leaves the app.
struct IslandDemoMarker: View {
    @ObservedObject var demo: IslandDemo = .shared

    var body: some View {
        if demo.hasStarted {
            Text(verbatim: "island")
                .font(.system(size: 1))
                .foregroundStyle(.clear)
                .accessibilityIdentifier("lk.island.started")
                .allowsHitTesting(false)
        } else if let failure = demo.failure {
            Text(verbatim: failure)
                .font(.system(size: 1))
                .foregroundStyle(.clear)
                .accessibilityIdentifier("lk.island.failed")
                .accessibilityLabel(failure)
                .allowsHitTesting(false)
        }
    }
}

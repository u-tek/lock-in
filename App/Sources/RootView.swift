import Core
import DesignSystem
import Paywall
import SessionEngine
import Social
import SwiftUI

/// Onboarding until it's done, then Home. Whenever a session exists, it covers either.
struct RootView: View {
    @ObservedObject var engine: SessionEngine
    @ObservedObject var plus: PlusStore
    @ObservedObject var account: AccountStore
    let social: SocialModels

    @State private var hasOnboarded: Bool
    @State private var showsSession = false
    @Environment(\.scenePhase) private var scenePhase
    /// Alerts: a Join that didn't go through says why here (M4).
    @ObservedObject private var alerts: NotificationInbox = AppServices.notificationInbox

    init(engine: SessionEngine, plus: PlusStore, social: SocialModels) {
        self.engine = engine
        self.plus = plus
        self.account = social.account
        self.social = social
        // Someone with finished sessions has been through it, even if the flag went missing
        // (a reinstall that kept the App Group, say).
        _hasOnboarded = State(initialValue: OnboardingState.isComplete() || engine.stats.completedSessions > 0)
    }

    var body: some View {
        ZStack {
            if hasOnboarded {
                HomeScreen(engine: engine, plus: plus, social: social)
                    .transition(.opacity)
            } else {
                OnboardingFlow(engine: engine, plus: plus) {
                    OnboardingState.markComplete()
                    hasOnboarded = true
                }
                .transition(.opacity)
            }
        }
        .fullScreenCover(isPresented: $showsSession) {
            SessionCover(engine: engine, plus: plus, social: social)
        }
        .errorAlert("Couldn't join", message: $alerts.failure)
        .onChange(of: engine.phase, initial: true) { oldPhase, phase in
            showsSession = phase != .idle
            // Back on Home after a session: a room may have opened or closed meanwhile.
            if phase == .idle, oldPhase != .idle {
                refreshSquads()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                engine.reconcile()
                refreshSquads()
            }
        }
        // Squads come with the account: at launch when already signed in, and after signing in.
        .task(id: account.state.isSignedIn) {
            await social.refreshSquads()
        }
        // Friends see the Lockling on this phone: send it when signing in and whenever it changes.
        .onChange(of: account.state) { _, state in
            if state.isSignedIn {
                syncAvatar()
            }
        }
        .onChange(of: engine.avatar) {
            syncAvatar()
        }
        .onOpenURL { url in
            open(url)
        }
    }

    private func refreshSquads() {
        let social = self.social
        Task {
            await social.refreshSquads()
        }
    }

    private func syncAvatar() {
        let avatar = engine.avatar
        let account = self.account
        Task {
            await account.updateAvatar(avatar)
        }
    }

    private func open(_ url: URL) {
        guard let link = DeepLink(url: url) else {
            Log.app.info("Ignored a link the app doesn't handle")
            return
        }
        switch link {
        case .session:
            // Tapping the Live Activity: the session cover is already up while a session runs.
            // Catch up in case it finished while the app was away.
            engine.reconcile()
        case .invite(let invite):
            // Home opens Friends for it (once no session is in the way), signing in first if
            // need be; the Friends screen then redeems it (`redeemInvite`): a squad to join, or
            // a friend to add.
            social.friends.openInvite(invite)
        }
    }
}

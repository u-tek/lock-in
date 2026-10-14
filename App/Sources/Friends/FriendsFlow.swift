import API
import AuthenticationServices
import DesignSystem
import Model
import Social
import SwiftUI

/// "Lock in with friends": one sheet that takes you from wherever you are to your friends. No
/// server: it says friends are coming. Signed out: Sign in with Apple. No handle yet: the handle
/// picker. Then Friends. From Settings' "Sign in" (`.signIn`), it closes once you're in.
struct FriendsFlow: View {
    enum Purpose {
        case friends
        case signIn
    }

    enum Step: Equatable {
        case unavailable
        case signIn
        case handle
        case friends

        /// The pitch steps sit in a shorter sheet; the ones with fields and lists get the screen.
        var isCompact: Bool {
            self == .unavailable || self == .signIn
        }
    }

    @ObservedObject var account: AccountStore
    let friends: FriendsStore
    let avatar: AvatarCode
    let purpose: Purpose

    /// When the island's made-up friends' timers were read.
    @State private var now: Date
    @State private var detent: PresentationDetent
    @Environment(\.dismiss) private var dismiss

    /// Tall enough for the island, the line and the button on an iPhone SE.
    private static let compact = PresentationDetent.fraction(0.62)

    init(social: SocialModels, avatar: AvatarCode, purpose: Purpose = .friends, now: Date = Date()) {
        self.account = social.account
        friends = social.friends
        self.avatar = avatar
        self.purpose = purpose
        _now = State(initialValue: now)
        let step = Self.step(for: social.account)
        _detent = State(initialValue: step.isCompact ? Self.compact : .large)
    }

    static func step(for account: AccountStore) -> Step {
        guard account.isConfigured else { return .unavailable }
        switch account.state {
        case .signedOut: return .signIn
        case .needsHandle: return .handle
        case .signedIn: return .friends
        }
    }

    private var step: Step {
        Self.step(for: account)
    }

    var body: some View {
        ZStack {
            switch step {
            case .unavailable:
                FriendsUnavailableStep(now: now)
                    .transition(.opacity)
            case .signIn:
                SignInStep(account: account, now: now)
                    .transition(.opacity)
            case .handle:
                if let user = account.user {
                    HandlePickerStep(account: account, user: user, avatar: avatar)
                        .transition(.opacity)
                }
            case .friends:
                if purpose == .friends {
                    FriendsScreen(account: account, friends: friends) {
                        dismiss()
                    }
                    .transition(.opacity)
                }
            }
        }
        .animation(.smooth, value: step)
        .presentationDetents([Self.compact, .large], selection: $detent)
        .presentationDragIndicator(step.isCompact ? .visible : .hidden)
        .onChange(of: step) { _, step in
            withAnimation(.smooth) {
                detent = step.isCompact ? Self.compact : .large
            }
            if purpose == .signIn, step == .friends {
                dismiss()
            }
        }
    }
}

/// Without a server (`LK_API_HOST` empty) there's nothing to sign into: the picture, and a line
/// saying friends are on their way.
struct FriendsUnavailableStep: View {
    let now: Date

    var body: some View {
        VStack(spacing: LKSpacing.xl) {
            FriendsIsland(now: now)
                .frame(maxWidth: 380)
                .padding(.top, LKSpacing.xxl)
            Text("Friends arrive when the Lockin server is set up")
                .font(LKFont.body)
                .foregroundStyle(LKColor.textSecondary)
                .multilineTextAlignment(.center)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, LKSpacing.xl)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

/// Signed out: the island with friends in it, one line, and Sign in with Apple.
struct SignInStep: View {
    @ObservedObject var account: AccountStore
    let now: Date

    @StateObject private var model = SignInModel()
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: LKSpacing.xl) {
            FriendsIsland(now: now)
                .frame(maxWidth: 380)
                .padding(.top, LKSpacing.xxl)
            Text("Add friends to see them in your Dynamic Island")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            signInButton
                .frame(height: 50)
        }
        .padding(.horizontal, LKSpacing.xl)
        .padding(.bottom, LKSpacing.l)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .errorAlert("Couldn't sign in", message: $model.failure)
    }

    @ViewBuilder
    private var signInButton: some View {
        if model.isWorking || account.isRestoring {
            ProgressView()
        } else {
            // The button may call back off the main thread: both closures are Sendable and hop
            // to the main actor with plain values.
            let signIn = self.model
            let account = self.account
            SignInWithAppleButton(.signIn) { @Sendable request in
                request.requestedScopes = [.fullName]
            } onCompletion: { @Sendable result in
                let outcome = AppleSignInOutcome(result)
                Task { @MainActor in
                    await signIn.finish(outcome, account: account)
                }
            }
            // White on dark, black on light (Apple's guidelines). Full width and a capsule, like
            // the app's other main buttons.
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .clipShape(Capsule())
            // The style is fixed when the button is made: a new one when the appearance changes.
            .id(colorScheme)
        }
    }
}

/// Sign in with Apple's result, taken to the account store.
@MainActor
final class SignInModel: ObservableObject {
    @Published private(set) var isWorking = false
    @Published var failure: String? = nil

    func finish(_ outcome: AppleSignInOutcome, account: AccountStore) async {
        switch outcome {
        case .cancelled:
            return
        case .failed:
            failure = "Sign in with Apple didn't go through. Please try again."
        case let .credential(identityToken, authorizationCode, givenName):
            isWorking = true
            defer { isWorking = false }
            do {
                try await account.signIn(identityToken: identityToken, authorizationCode: authorizationCode, displayName: givenName)
            } catch is CancellationError {
                return
            } catch {
                failure = error.localizedDescription
            }
        }
    }
}

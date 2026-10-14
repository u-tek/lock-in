import API
import AuthenticationServices
import Creature
import DesignSystem
import Model
import Social
import SwiftUI

/// A friend's Lockling on a disc of its own colour: the avatar in lists and headers.
struct FriendAvatar: View {
    let avatar: AvatarCode
    var pose: CreaturePose = .idle
    var size: CGFloat = 44

    var body: some View {
        CreatureView(avatar: avatar, pose: pose, size: size * 0.74)
            .frame(width: size, height: size)
            .background(CreatureCatalogue.colour(avatar.colour).opacity(0.16), in: Circle())
            .accessibilityHidden(true)
    }
}

/// A friend in a list: Lockling, name, @handle.
struct FriendRow: View {
    let friend: Friend

    var body: some View {
        HStack(spacing: LKSpacing.m) {
            FriendAvatar(avatar: friend.avatar)
            VStack(alignment: .leading, spacing: 1) {
                Text(friend.name)
                    .font(LKFont.body.weight(.semibold))
                if let handle = friend.handle {
                    Text(verbatim: "@\(handle)")
                        .font(LKFont.subheadline)
                        .foregroundStyle(LKColor.textSecondary)
                }
            }
            .lineLimit(1)
        }
        .padding(.vertical, LKSpacing.xxs)
        .accessibilityElement(children: .combine)
    }
}

/// An invite link's QR code: black on white, whatever the appearance, because that's what
/// cameras read best. Made once per link.
struct QRCodeImage: View {
    let text: String

    var body: some View {
        Group {
            if let image = QRCodeCache.image(for: text) {
                image
                    .aspectRatio(1, contentMode: .fit)
            } else {
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
            }
        }
        .accessibilityLabel("QR code")
    }
}

@MainActor
private enum QRCodeCache {
    private static var images: [String: Image] = [:]

    static func image(for text: String) -> Image? {
        if let cached = images[text] {
            return cached
        }
        let image = FriendCodeQR.image(for: text)
        images[text] = image
        return image
    }
}

/// What Sign in with Apple handed back, taken apart into plain values so it can cross to the
/// main actor whichever thread the button calls back on.
enum AppleSignInOutcome: Sendable {
    case credential(identityToken: String, authorizationCode: String?, givenName: String?)
    /// The person closed the sheet: not an error.
    case cancelled
    case failed

    init(_ result: Result<ASAuthorization, any Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8)
            else {
                self = .failed
                return
            }
            self = .credential(
                identityToken: token,
                authorizationCode: credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) },
                givenName: credential.fullName?.givenName
            )
        case .failure(let error):
            if let error = error as? ASAuthorizationError, error.code == .canceled {
                self = .cancelled
            } else {
                self = .failed
            }
        }
    }
}

extension View {
    /// An alert for a failure message; dismissing it clears the message.
    func errorAlert(_ title: LocalizedStringKey, message: Binding<String?>) -> some View {
        alert(
            title,
            isPresented: Binding(
                get: { message.wrappedValue != nil },
                set: { if !$0 { message.wrappedValue = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}

/// A `Binding<Bool>` that's true while an optional holds something, for dialogs that present an
/// item.
func isPresent<Item: Sendable>(_ item: Binding<Item?>) -> Binding<Bool> {
    Binding(
        get: { item.wrappedValue != nil },
        set: { if !$0 { item.wrappedValue = nil } }
    )
}

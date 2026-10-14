import Combine
import FamilyControls
import Foundation

/// Whether Lockin may shield apps: Screen Time access for the person's own device
/// (FamilyControls' individual authorization), and before that, Apple's approval.
///
/// Until Apple approves the Family Controls (Distribution) entitlement the app ships without it
/// (docs/milestones/M8.md). Then `status` is `.notEntitled` and FamilyControls is never touched,
/// so the Deep Focus row can say it's waiting on Apple instead of offering a picker that would fail.
@MainActor
public final class DeepFocusAuthorization: ObservableObject {
    public enum Status: Equatable, Sendable {
        /// This build isn't signed with Family Controls: Apple hasn't approved it yet. Show
        /// "Waiting on Apple"; there's nothing the person can do.
        case notEntitled
        /// Never asked, or asked in an earlier launch and not yet confirmed in this one.
        /// `request()` asks; once approved, asking again shows nothing and just confirms.
        case notDetermined
        /// The person said no, or switched Lockin off in Settings > Screen Time.
        case denied
        /// Lockin can shield apps.
        case approved

        /// Our status from the entitlement and FamilyControls' status.
        public init(isEntitled: Bool, system: AuthorizationStatus) {
            guard isEntitled else {
                self = .notEntitled
                return
            }
            switch system {
            case .notDetermined: self = .notDetermined
            case .denied: self = .denied
            // `.approved`, and `.approvedWithDataAccess` (iOS 26.4), which allows everything
            // `.approved` does and more.
            default: self = .approved
            }
        }
    }

    /// Why asking didn't work, in words for an alert.
    public enum Failure: Error, Equatable, Sendable, LocalizedError {
        /// Screen Time restrictions (a parent's, or a device management profile) don't allow it.
        case restricted
        /// Individual authorization needs a passcode on the phone.
        case noPasscode
        case network
        /// FamilyControls couldn't start, or isn't offered in this region or on this device.
        case unavailable
        case failed

        public var errorDescription: String? {
            switch self {
            case .restricted: "Screen Time restrictions on this iPhone don't allow Deep Focus."
            case .noPasscode: "Deep Focus needs a passcode on this iPhone. Set one in Settings, then try again."
            case .network: "Couldn't reach Apple. Check your connection and try again."
            case .unavailable: "Screen Time isn't available to Lockin on this iPhone right now."
            case .failed: "Something went wrong turning on Deep Focus. Please try again."
            }
        }

        /// Sorts what FamilyControls threw. Nil when the person cancelled, which isn't an error.
        public init?(_ error: Error) {
            if let failure = error as? Failure {
                self = failure
                return
            }
            guard let error = error as? FamilyControlsError else {
                self = .failed
                return
            }
            switch error {
            case .authorizationCanceled: return nil
            case .restricted, .authorizationConflict: self = .restricted
            case .authenticationMethodUnavailable: self = .noPasscode
            case .networkError: self = .network
            case .unavailable: self = .unavailable
            default: self = .failed
            }
        }
    }

    @Published public private(set) var status: Status
    /// Whether this build carries the Family Controls entitlement.
    public let isEntitled: Bool
    private let isPreview: Bool
    private var observation: Task<Void, Never>?

    /// Reads the entitlement from this build's signature.
    public convenience init() {
        self.init(isEntitled: SignedEntitlements.grantsFamilyControls)
    }

    /// - Parameter isEntitled: Whether to treat the build as entitled. The app passes nothing and
    ///   gets the signature's answer; this is for a debug override.
    public init(isEntitled: Bool) {
        self.isEntitled = isEntitled
        self.isPreview = false
        if isEntitled {
            status = Status(isEntitled: true, system: AuthorizationCenter.shared.authorizationStatus)
            observe()
        } else {
            status = .notEntitled
        }
    }

    private init(preview status: Status) {
        self.isEntitled = status != .notEntitled
        self.isPreview = true
        self.status = status
    }

    /// Never touches FamilyControls, for snapshots and SwiftUI previews.
    public static func preview(_ status: Status) -> DeepFocusAuthorization {
        DeepFocusAuthorization(preview: status)
    }

    deinit {
        observation?.cancel()
    }

    /// Asks for Screen Time access to this device (individual authorization: Face ID or the
    /// passcode, no parent). Already approved, it asks nothing and confirms. Not entitled, it does
    /// nothing. Throws `Failure`; cancelling isn't one.
    public func request() async throws {
        guard isEntitled, !isPreview else { return }
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        } catch {
            refresh()
            if let failure = Failure(error) {
                deepFocusLog.error("Screen Time authorization failed: \(String(describing: failure), privacy: .public)")
                throw failure
            }
            return
        }
        refresh()
    }

    /// Reads FamilyControls' status again: at launch, on return to the foreground (it can be
    /// switched off in Settings), and after `request()`.
    public func refresh() {
        guard isEntitled, !isPreview else { return }
        set(Status(isEntitled: true, system: AuthorizationCenter.shared.authorizationStatus))
    }

    /// FamilyControls publishes the status once it knows it, which may be a moment after launch.
    private func observe() {
        observation = Task { [weak self] in
            for await value in AuthorizationCenter.shared.$authorizationStatus.values {
                self?.set(Status(isEntitled: true, system: value))
            }
        }
    }

    private func set(_ new: Status) {
        if status != new {
            status = new
        }
    }
}

import FamilyControls
import Foundation

/// The apps, categories and websites the person chose to block, kept in the App Group so the
/// extensions can shield them.
///
/// The picker hands back a `FamilyActivitySelection` of opaque tokens: Lockin never learns which
/// apps they are. Present it with SwiftUI's `.familyActivityPicker(isPresented:selection:)`
/// (FamilyControls), starting from `load()`, then `save(_:)` what comes back and tell the
/// controller (`DeepFocusController.selectionDidChange()`) so a running session picks it up.
public struct DeepFocusSelection: Sendable {
    let url: URL
    private let storage: DeepFocusStorage

    public init(storage: DeepFocusStorage = .appGroup()) {
        self.storage = storage
        self.url = storage.selectionURL
    }

    /// What was saved, or an empty selection.
    public func load() -> FamilyActivitySelection {
        SharedFile.read(FamilyActivitySelection.self, from: url) ?? FamilyActivitySelection()
    }

    public func save(_ selection: FamilyActivitySelection) throws {
        try storage.prepare()
        try SharedFile.write(selection, to: url)
    }

    /// Forgets the choice, for turning Deep Focus off.
    public func clear() {
        try? FileManager.default.removeItem(at: url)
    }

    /// Counts for the Deep Focus row: "3 apps, 1 category".
    public var summary: Summary {
        Summary(load())
    }

    public struct Summary: Equatable, Sendable {
        public var applications: Int
        public var categories: Int
        public var webDomains: Int

        /// ManagedSettings shields at most 50 apps, 50 websites and 50 categories at once
        /// (ShieldSettings); past that, an arbitrary 50 are shielded.
        public static let limit = 50

        public init(applications: Int, categories: Int, webDomains: Int) {
            self.applications = applications
            self.categories = categories
            self.webDomains = webDomains
        }

        public init(_ selection: FamilyActivitySelection) {
            self.init(
                applications: selection.applicationTokens.count,
                categories: selection.categoryTokens.count,
                webDomains: selection.webDomainTokens.count
            )
        }

        /// Nothing chosen: a session has nothing to shield.
        public var isEmpty: Bool {
            total == 0
        }

        public var total: Int {
            applications + categories + webDomains
        }

        /// More of something than ManagedSettings will shield; worth a word in the picker's row.
        public var isOverLimit: Bool {
            applications > Self.limit || categories > Self.limit || webDomains > Self.limit
        }
    }
}

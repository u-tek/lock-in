import DesignSystem
import LiveActivity
import SwiftUI

/// M0's home: what the app is, a preview of the squad on the Lock Screen, what's coming, and the
/// Developer menu. Nothing here pretends to work yet; solo sessions arrive in M1.
///
/// An inset-grouped list under a large title, like Settings: the pitch is a feature header (an
/// icon, a title and a line under it, as Settings introduces Screen Time or Focus), and every
/// other part is a section with the system's own header and footer.
struct HomeScreen: View {
    let showsDeveloperTools: Bool
    /// The instant the preview's timers count from. Held in state so the preview doesn't restart
    /// whenever the parent redraws.
    @State private var previewDate: Date

    init(showsDeveloperTools: Bool, previewDate: Date = Date()) {
        self.showsDeveloperTools = showsDeveloperTools
        _previewDate = State(initialValue: previewDate)
    }

    var body: some View {
        // Everyone focusing, so the island reads "+3": the moment the product is built around.
        let sample = LiveActivitySamples.squadOfFour(now: previewDate)
        List {
            Section {
                Pitch()
            }

            Section {
                SquadPreview(sample: sample)
                    .activityStageRow(.wallpaper)
            } header: {
                Text("Preview")
            } footer: {
                Text("A made-up squad, as it would sit in your Dynamic Island and on your Lock Screen.")
            }

            Section {
                Label {
                    VStack(alignment: .leading, spacing: LKSpacing.xxs) {
                        Text("Solo sessions")
                        Text("25, 50 or 90 minutes, with your own Live Activity. They arrive in the next build; squads follow once accounts do.")
                            .font(LKFont.subheadline)
                            .foregroundStyle(LKColor.textSecondary)
                    }
                } icon: {
                    LKIconTile(systemName: "timer", color: .orange)
                }
            } header: {
                Text("Coming next")
            }

            if showsDeveloperTools {
                Section {
                    NavigationLink(value: AppRoute.developer) {
                        Label {
                            Text("Developer")
                        } icon: {
                            // Settings' own Developer row: a hammer on grey.
                            LKIconTile(systemName: "hammer.fill", color: .gray)
                        }
                    }
                } footer: {
                    Text("The APNs spike, the Live Activity Lab and the design tokens. Off in App Store builds.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Lockin")
        .navigationBarTitleDisplayMode(.large)
    }
}

/// What Lockin is, in the shape of a Settings feature header: a large tile, a title and one line.
private struct Pitch: View {
    var body: some View {
        VStack(spacing: LKSpacing.s) {
            LKIconTile(systemName: "lock.fill", color: LKColor.tint, size: 56)
                .padding(.bottom, LKSpacing.xs)
            Text("Lock in with your friends.")
                .font(LKFont.title2.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            Text("Your squad's focus timers sit in your Dynamic Island and on your Lock Screen while you work.")
                .font(LKFont.subheadline)
                .foregroundStyle(LKColor.textSecondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, LKSpacing.s)
    }
}

/// The squad as a phone would show it: the compact island above, the Lock Screen card below, on a
/// stand-in wallpaper.
private struct SquadPreview: View {
    let sample: LiveActivitySample

    var body: some View {
        VStack(spacing: LKSpacing.l) {
            CompactIslandPreview(sample)
                // The card below says the same, in full.
                .accessibilityHidden(true)
            LockScreenPreview(sample)
        }
    }
}

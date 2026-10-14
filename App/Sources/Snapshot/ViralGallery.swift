import DesignSystem
import Model
import SessionEngine
import ShareCards
import SwiftUI
import UIKit
import WidgetKit
import WidgetViews

// The M6 snapshot routes' screens: the widgets drawn by the WidgetViews module in stand-ins for
// the Home Screen and the Lock Screen (`widgets.*`), and the share cards as ShareCardRenderer
// renders them (`share.*`). Only the views inside the frames are real; the system's own widget
// chrome, the wallpaper and the vibrant Lock Screen rendering are checked on a phone through
// TestFlight, as the Live Activity's are (docs/decisions/0001-live-activity-views-in-package.md).

/// Widget sizes on an iPhone 16 Pro, in points, from Apple's widget size table; worth a check on
/// the phone itself when they look off.
enum WidgetPreviewMetrics {
    static let small = CGSize(width: 170, height: 170)
    static let medium = CGSize(width: 364, height: 170)
    static let circular = CGSize(width: 76, height: 76)
    static let rectangular = CGSize(width: 172, height: 76)
    /// The system's margin round a Home Screen widget's content.
    static let contentMargin: CGFloat = 16
    /// A Home Screen widget's corner.
    static let cornerRadius: CGFloat = 23
    /// Between widgets, roughly the Home Screen's gap.
    static let spacing: CGFloat = 12

    static func size(_ family: WidgetFamily) -> CGSize {
        switch family {
        case .systemMedium: medium
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        default: small
        }
    }
}

/// One page of widgets for the design snapshots.
struct WidgetGalleryScreen: View {
    enum Panel {
        /// `widgets.pet`: the Squad pet widget, small and medium, a squad's and yours.
        case pet
        /// `widgets.lockin`: the Lock in widget idle, running and paused, and the control.
        case lockIn
        /// `widgets.accessory`: the Lock Screen families on a wallpaper, in one colour.
        case accessory
    }

    let panel: Panel
    let avatar: AvatarCode
    let now: Date

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LKSpacing.l) {
                switch panel {
                case .pet: petPanel
                case .lockIn: lockInPanel
                case .accessory: accessoryPanel
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, LKSpacing.l)
        }
        .background(LKColor.groupedBackground)
    }

    // MARK: Squad pet

    @ViewBuilder
    private var petPanel: some View {
        let squads = WidgetSamples.squads(avatar: avatar, now: now)
        let solo = WidgetSamples.solo(avatar: avatar, now: now)
        GalleryRow("A squad's pet, and a new squad's egg") {
            HomeWidget(.systemSmall, content: PetWidgetContent(data: squads, squadID: nil))
            HomeWidget(.systemSmall, content: PetWidgetContent(data: squads, squadID: WidgetSamples.newSquad.id))
        }
        GalleryRow("Medium") {
            HomeWidget(.systemMedium, content: PetWidgetContent(data: squads, squadID: nil))
        }
        GalleryRow("No squad yet; a squad on a tinted Home Screen") {
            HomeWidget(.systemSmall, content: PetWidgetContent(data: solo, squadID: nil))
            HomeWidget(.systemSmall, content: PetWidgetContent(data: squads, squadID: nil), isFullColor: false)
        }
        GalleryRow("Medium, no squad") {
            HomeWidget(.systemMedium, content: PetWidgetContent(data: solo, squadID: nil))
        }
    }

    // MARK: Lock in

    @ViewBuilder
    private var lockInPanel: some View {
        GalleryRow("Lock in, and ten minutes in") {
            LockInHomeWidget(data: WidgetSamples.solo(avatar: avatar, now: now), now: now)
            LockInHomeWidget(data: WidgetSamples.running(avatar: avatar, now: now), now: now)
        }
        GalleryRow("Paused in a squad, and tinted") {
            LockInHomeWidget(data: WidgetSamples.paused(avatar: avatar, now: now), now: now)
            LockInHomeWidget(data: WidgetSamples.solo(avatar: avatar, now: now), now: now, isFullColor: false)
        }
        GalleryRow("Control Center") {
            ControlPreview()
        }
    }

    // MARK: Lock Screen

    private var accessoryPanel: some View {
        let squads = WidgetSamples.squads(avatar: avatar, now: now)
        let solo = WidgetSamples.solo(avatar: avatar, now: now)
        return VStack(spacing: LKSpacing.xl) {
            Text(verbatim: "9:41")
                .font(.system(size: 88, weight: .semibold))
                .monospacedDigit()
            VStack(spacing: LKSpacing.l) {
                HStack(spacing: LKSpacing.m) {
                    LockScreenWidget(.accessoryCircular, content: PetWidgetContent(data: squads, squadID: nil))
                    LockScreenWidget(.accessoryCircular, content: PetWidgetContent(data: squads, squadID: WidgetSamples.newSquad.id))
                    LockScreenWidget(.accessoryRectangular, content: PetWidgetContent(data: squads, squadID: nil))
                }
                HStack(spacing: LKSpacing.m) {
                    LockScreenWidget(.accessoryCircular, content: PetWidgetContent(data: solo, squadID: nil))
                    LockScreenWidget(.accessoryRectangular, content: PetWidgetContent(data: solo, squadID: nil))
                }
            }
            Text("The Lock Screen draws these in one colour over the wallpaper. Left to right: a squad's pet, a new squad's egg, the squad in words; then yours with no squad.")
                .font(LKFont.footnote)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, LKSpacing.xl)
        }
        .foregroundStyle(.white)
        .padding(.vertical, LKSpacing.xxl)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [LKColor.tint.mix(with: .black, by: 0.5), Color.teal.mix(with: .black, by: 0.55)],
                startPoint: .top,
                endPoint: .bottom
            ),
            in: RoundedRectangle(cornerRadius: LKRadius.card, style: .continuous)
        )
        .environment(\.colorScheme, .dark)
        .padding(.horizontal, LKSpacing.s)
    }
}

/// A caption and a row of widgets, centred.
private struct GalleryRow<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LKSpacing.s) {
            Text(title)
                .font(LKFont.footnote.weight(.medium))
                .foregroundStyle(LKColor.textSecondary)
                .padding(.horizontal, LKSpacing.gutter)
            HStack(spacing: WidgetPreviewMetrics.spacing) {
                content
            }
            .frame(maxWidth: .infinity)
        }
    }
}

/// A Squad pet widget as the Home Screen shows it: inside the system's margins, on its surface,
/// with the widget's corners. The App Store screenshots use it too.
struct HomeWidget: View {
    let family: WidgetFamily
    let content: PetWidgetContent
    let isFullColor: Bool

    init(_ family: WidgetFamily, content: PetWidgetContent, isFullColor: Bool = true) {
        self.family = family
        self.content = content
        self.isFullColor = isFullColor
    }

    var body: some View {
        HomeWidgetFrame(family: family, accent: content.accent, isFullColor: isFullColor) {
            SquadPetWidgetView(content: content, family: family, isFullColor: isFullColor)
        }
    }
}

struct LockInHomeWidget: View {
    let data: WidgetData
    let now: Date
    var isFullColor = true

    var body: some View {
        HomeWidgetFrame(family: .systemSmall, accent: LockInWidgetView.accent, isFullColor: isFullColor) {
            LockInWidgetView(data: data, now: now, isFullColor: isFullColor)
        }
    }
}

/// The Home Screen's frame round a widget. Out of full colour it stands in for the tinted Home
/// Screen: the system takes the surface away and draws the content in one tone on a dark glass.
private struct HomeWidgetFrame<Content: View>: View {
    let family: WidgetFamily
    let accent: Color
    let isFullColor: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        let size = WidgetPreviewMetrics.size(family)
        let shape = RoundedRectangle(cornerRadius: WidgetPreviewMetrics.cornerRadius, style: .continuous)
        Group {
            if isFullColor {
                content()
                    .padding(WidgetPreviewMetrics.contentMargin)
                    .frame(width: size.width, height: size.height)
                    .background(WidgetSurface(accent: accent))
            } else {
                content()
                    .padding(WidgetPreviewMetrics.contentMargin)
                    .frame(width: size.width, height: size.height)
                    .foregroundStyle(.white)
                    .background(Color.black.opacity(0.75))
                    .environment(\.colorScheme, .dark)
            }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(LKColor.separator, lineWidth: 0.5))
    }
}

/// A Lock Screen widget at its size, with a faint outline to show its bounds.
private struct LockScreenWidget: View {
    let family: WidgetFamily
    let content: PetWidgetContent

    init(_ family: WidgetFamily, content: PetWidgetContent) {
        self.family = family
        self.content = content
    }

    var body: some View {
        let size = WidgetPreviewMetrics.size(family)
        SquadPetWidgetView(content: content, family: family, isFullColor: false)
            .frame(width: size.width, height: size.height)
            .overlay {
                if family == .accessoryRectangular {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                }
            }
    }
}

/// The Control Center control: a round button with the lock, and its name under it. The system
/// draws the real one from `ControlWidgetButton`'s label.
private struct ControlPreview: View {
    var body: some View {
        VStack(spacing: LKSpacing.s) {
            Image(systemName: "lock.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 68, height: 68)
                .background(Color.black.opacity(0.55), in: Circle())
            Text("Lock in")
                .font(LKFont.caption.weight(.medium))
                .foregroundStyle(LKColor.textSecondary)
        }
        .frame(width: WidgetPreviewMetrics.small.width)
    }
}

// MARK: - Share cards

/// A share card as the renderer draws it, scaled to fit the screen on black: what goes to the
/// share sheet, pixel for pixel, only smaller.
struct ShareCardPreview: View {
    private let image: UIImage?

    init(card: ShareCard, kind: ShareCardKind) {
        image = ShareCardRenderer.uiImage(card, kind: kind)
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                ContentUnavailableView("Couldn't render the card", systemImage: "photo")
            }
        }
    }
}

/// The made-up sessions the share snapshots show: Sam's squad (the pitch's three friends) and Sam
/// alone.
@MainActor
enum ShareSamples {
    /// Fifty minutes with the squad, a teen sprout, and Sam's friend code.
    static var squad: ShareCard {
        ShareCard(
            avatar: SampleLocklings.you,
            name: "Sam",
            squadName: "Library Goblins",
            squadmates: SampleLocklings.friends.map { friend in
                ShareCard.Member(id: friend.id, name: friend.name, avatar: friend.avatar)
            },
            minutes: 50,
            streak: 4,
            pet: PetCode("sprout.2"),
            petMood: PetMood.happy.rawValue,
            inviteCode: "KQ7M2XPA"
        )
    }

    /// Twenty-five minutes alone, signed out: no code to share yet.
    static var solo: ShareCard {
        ShareCard(avatar: SampleLocklings.you, minutes: 25, streak: 3)
    }

    /// The squad's fifty minutes, just finished.
    static func record(now: Date) -> SessionRecord {
        SessionRecord(
            id: "snapshot",
            startedAt: now.addingTimeInterval(-3_000),
            endedAt: now,
            plannedMinutes: 50,
            focusedSeconds: 3_000,
            completed: true,
            coinsEarned: 55
        )
    }
}

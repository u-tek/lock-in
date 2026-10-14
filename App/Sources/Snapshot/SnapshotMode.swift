import API
import DeepFocus
import LiveActivity
import Model
import Paywall
import SessionEngine
import ShareCards
import Social
import SwiftUI
import UIKit

/// Shows screens in a fixed state for the UI snapshot exporter (`UITests/SnapshotExportTests`).
///
/// Launch argument: `-LKSnapshots home@light,home@dark,session@dark,...`. The app shows the first,
/// then steps to the next each time the exporter posts the `next` Darwin notification, so one
/// launch covers every screen. Arguments in this form land in the `UserDefaults` argument domain,
/// so they never persist.
///
/// Nothing in snapshot mode touches ActivityKit, StoreKit, the App Group, the Keychain, the
/// network or a permission prompt: app screens get preview models, the spike screen gets a fixed
/// state, and orphaned activities are left alone.
struct SnapshotMode: Sendable {
    enum Appearance: String, Sendable {
        case light
        case dark

        var colorScheme: ColorScheme {
            switch self {
            case .light: .light
            case .dark: .dark
            }
        }
    }

    struct Shot: Sendable {
        let route: String
        /// Nil follows the simulator's own appearance, as the app does outside snapshot mode.
        let appearance: Appearance?
    }

    /// Posted by the exporter after each capture.
    static let nextNotification = "com.lockin.snapshot.next"

    let shots: [Shot]

    /// The one instant every sample in this run is built from, so every screen shows the same
    /// made-up squad at the same moment.
    ///
    /// It's the launch, not a constant: SwiftUI's timers (`Text(timerInterval:)`) read the device
    /// clock, which nothing here can pin. A constant date in the past would draw every running
    /// timer at 0:00; from the launch, a timer reads as designed ("15:00" for Ava), less the few
    /// seconds before its screen is captured.
    let referenceDate: Date

    static let current: SnapshotMode? = {
        guard let list = UserDefaults.standard.string(forKey: "LKSnapshots"), !list.isEmpty else { return nil }
        let shots = list.split(separator: ",").compactMap { token -> Shot? in
            let parts = token.split(separator: "@", maxSplits: 1).map(String.init)
            guard let route = parts.first?.trimmingCharacters(in: .whitespaces), !route.isEmpty else { return nil }
            let appearance = parts.count > 1 ? Appearance(rawValue: parts[1]) : nil
            return Shot(route: route, appearance: appearance)
        }
        return shots.isEmpty ? nil : SnapshotMode(shots: shots, referenceDate: Date())
    }()
}

/// Every screen the exporter can open, by route name. `scripts/snapshot-routes.txt` lists the
/// ones CI exports; `lab.*` routes render on the iPhone 16 Pro only.
///
/// App screens get preview models (`SessionEngine.preview`, `PlusStore.preview`,
/// `AccountStore.preview`, `FriendsStore.preview`, `SquadsStore.preview`, `SquadRooms.preview`):
/// no store, no ActivityKit, no StoreKit, no server and no permission prompts. Sheets and covers
/// are shown as screens of their own. A squad session's room is handed to the session screen
/// directly, because the preview engine runs solo.
@MainActor
enum SnapshotGallery {
    static func view(for route: String, now: Date) -> AnyView? {
        switch route {
        // First run
        case "onboarding.welcome":
            return onboarding(.welcome, now: now)
        case "onboarding.lockling":
            return onboarding(.lockling, now: now)
        case "onboarding.notifications":
            return onboarding(.notifications, now: now)
        case "onboarding.ready":
            return onboarding(.ready, now: now)
        case "onboarding.tips":
            // After the first finished session, in a sheet: the Lock Screen first (M6).
            return AnyView(OnboardingTipsView(tips: OnboardingTip.allCases, now: now, onDone: {}))
        case "onboarding.tips.standby":
            // Its second page: desk mode.
            return AnyView(OnboardingTipsView(tips: OnboardingTip.allCases, now: now, startAt: .deskMode, onDone: {}))

        // The app
        case "home":
            return AnyView(PreviewModels(stats: SnapshotData.regular) { engine, plus, social in
                HomeScreen(engine: engine, plus: plus, social: social)
            })
        case "home.squad":
            // In a squad whose room is open, with it picked: "Join in".
            return AnyView(PreviewModels(
                stats: SnapshotData.regular,
                account: .signedIn(SnapshotData.me),
                friends: SnapshotData.friends,
                squads: [SnapshotData.squad],
                roomCounts: [SnapshotData.squadSessionID: 3]
            ) { engine, plus, social in
                HomeScreen(engine: engine, plus: plus, social: social, squadID: SnapshotData.squad.id)
            })
        case "home.custom":
            // Lockin Plus's custom length (M7), from Home's Custom tile, shown as a screen.
            return AnyView(CustomLengthSheet(minutes: .constant(45)))
        case "session":
            // The first session, so the "lock your phone" hint shows.
            return AnyView(PreviewModels(phase: SnapshotData.running(now: now), stats: SnapshotData.newcomer) { engine, plus, social in
                SessionCover(engine: engine, plus: plus, social: social)
            })
        case "session.paused":
            return AnyView(PreviewModels(phase: SnapshotData.paused(now: now), stats: SnapshotData.regular) { engine, plus, social in
                SessionCover(engine: engine, plus: plus, social: social)
            })
        case "session.disabled":
            // Live Activities switched off in Settings: the session runs, and says how to fix it.
            return AnyView(PreviewModels(
                phase: SnapshotData.running(now: now),
                stats: SnapshotData.regular,
                liveActivityProblem: .disabled
            ) { engine, plus, social in
                SessionCover(engine: engine, plus: plus, social: social)
            })
        case "session.squad":
            // Ava focusing, Kai paused, Noor done.
            return AnyView(PreviewModels(phase: SnapshotData.running(now: now), stats: SnapshotData.regular, squads: [SnapshotData.squad]) { engine, plus, social in
                SessionCover(engine: engine, plus: plus, social: social, squad: SnapshotData.squadRoom(now: now))
            })
        case "session.cheer":
            return AnyView(PreviewModels(phase: SnapshotData.running(now: now), stats: SnapshotData.regular, squads: [SnapshotData.squad]) { engine, plus, social in
                SessionCover(
                    engine: engine,
                    plus: plus,
                    social: social,
                    squad: SnapshotData.squadRoom(now: now),
                    cheering: SnapshotData.friends[0].id
                )
            })
        case "finished":
            return AnyView(PreviewModels(phase: SnapshotData.finished(now: now), stats: SnapshotData.regular) { engine, plus, social in
                SessionCover(engine: engine, plus: plus, social: social)
            })
        case "finished.first":
            return AnyView(PreviewModels(phase: SnapshotData.finished(now: now), stats: SnapshotData.firstFinish) { engine, plus, social in
                SessionCover(engine: engine, plus: plus, social: social)
            })
        case "finished.squad":
            // The first squad session completed: Lockin Plus's moment.
            return AnyView(PreviewModels(phase: SnapshotData.finished(now: now), stats: SnapshotData.regular, squads: [SnapshotData.squad]) { engine, plus, social in
                SessionCover(engine: engine, plus: plus, social: social, firstSquadFinish: true)
            })
        case "finished.share":
            // After a squad session: Share beside Done, with the squad's card behind it (M6).
            return AnyView(FinishedScreen(
                record: ShareSamples.record(now: now),
                avatar: SampleLocklings.you,
                offersFriends: false,
                onFriends: {},
                share: ShareSamples.squad,
                onDone: {}
            ))
        case "finished.hatch":
            // The squad's egg hatched in this session (M5).
            guard case .finished(let record) = SnapshotData.finished(now: now) else { return nil }
            return AnyView(FinishedScreen(
                record: record,
                avatar: SampleLocklings.you,
                offersFriends: false,
                onFriends: {},
                squadPet: SnapshotData.hatch,
                onDone: {}
            ))
        case "shop":
            // From Home's coin count: 120 coins, wearing a beanie (M5).
            return AnyView(PreviewModels(stats: SnapshotData.regular) { engine, plus, social in
                ShopScreen(shop: social.shop, account: social.account, plus: plus, avatar: .constant(engine.avatar), onDone: {})
            })
        case "shop.bought":
            // The cap, just bought for 100 and on.
            let cap = ShopCatalogue.item(id: "hat.3")
            return AnyView(PreviewModels(
                stats: SnapshotData.regular,
                coins: 20,
                owned: ShopCatalogue.freeItemIDs(wornBy: SampleLocklings.you) + ["hat.3"]
            ) { engine, plus, social in
                ShopScreen(
                    shop: social.shop,
                    account: social.account,
                    plus: plus,
                    avatar: .constant(cap?.applied(to: engine.avatar) ?? engine.avatar),
                    bought: cap,
                    onDone: {}
                )
            })
        case "paywall":
            return AnyView(PreviewModels(stats: SnapshotData.regular) { engine, plus, _ in
                PaywallView(store: plus, avatar: engine.avatar, onClose: {})
            })
        case "settings":
            // Signed out: the Sign in row.
            return AnyView(PreviewModels(stats: SnapshotData.regular) { engine, plus, social in
                SettingsScreen(engine: engine, plus: plus, social: social, onClose: {})
            })
        case "settings.account":
            return AnyView(PreviewModels(stats: SnapshotData.regular, account: .signedIn(SnapshotData.me)) { engine, plus, social in
                SettingsScreen(engine: engine, plus: plus, social: social, onClose: {})
            })
        case "settings.plus":
            // Plus on (M7): its status, and the App Store's subscription sheet a tap away.
            return AnyView(PreviewModels(stats: SnapshotData.regular, isPlus: true, account: .signedIn(SnapshotData.me)) { engine, plus, social in
                SettingsScreen(engine: engine, plus: plus, social: social, onClose: {})
            })
        case "settings.notifications":
            // Squad alerts on, quiet hours 22:00 to 07:00 (M4).
            return AnyView(NavigationStack {
                NotificationSettingsScreen(snapshot: .authorised)
            })
        case "settings.deepfocus":
            // Plus, Screen Time approved, blocking on with four apps and a category chosen (M8).
            return AnyView(NavigationStack {
                DeepFocusScreen(
                    snapshot: .preview(
                        status: .approved,
                        isOn: true,
                        summary: DeepFocusSelection.Summary(applications: 4, categories: 1, webDomains: 0)
                    ),
                    isPlus: true
                )
            })
        case "settings.deepfocus.plus":
            // Without Plus: the offer (paywall moment 3).
            return AnyView(NavigationStack {
                DeepFocusScreen(snapshot: .preview(status: .notEntitled), isPlus: false)
            })
        case "settings.deepfocus.soon":
            // Plus, in a build Apple hasn't approved Family Controls for yet.
            return AnyView(NavigationStack {
                DeepFocusScreen(snapshot: .preview(status: .notEntitled), isPlus: true)
            })

        // Friends (sheets, shown as screens)
        case "friends.signin":
            return AnyView(PreviewModels(stats: SnapshotData.firstFinish) { engine, plus, social in
                FriendsFlow(social: social, plus: plus, avatar: engine.avatar, now: now)
            })
        case "friends.unavailable":
            // A build without LK_API_HOST.
            return AnyView(PreviewModels(stats: SnapshotData.firstFinish, isConfigured: false) { engine, plus, social in
                FriendsFlow(social: social, plus: plus, avatar: engine.avatar, now: now)
            })
        case "friends.username":
            // Just signed in; Apple shared a first name, and a free username is typed in.
            return AnyView(PreviewModels(
                stats: SnapshotData.firstFinish,
                account: .needsHandle(SnapshotData.newAccount),
                suggestedName: SnapshotData.me.displayName
            ) { engine, _, social in
                HandlePickerStep(
                    account: social.account,
                    user: SnapshotData.newAccount,
                    avatar: engine.avatar,
                    handle: SnapshotData.me.handle ?? "",
                    focusesField: false
                )
            })
        case "friends.list":
            return AnyView(PreviewModels(stats: SnapshotData.regular, account: .signedIn(SnapshotData.me), friends: SnapshotData.friends) { engine, plus, social in
                FriendsScreen(social: social, plus: plus, avatar: engine.avatar, onDone: {})
            })
        case "friends.empty":
            return AnyView(PreviewModels(stats: SnapshotData.firstFinish, account: .signedIn(SnapshotData.me)) { engine, plus, social in
                FriendsScreen(social: social, plus: plus, avatar: engine.avatar, onDone: {})
            })
        case "friends.add":
            return AnyView(PreviewModels(stats: SnapshotData.regular, account: .signedIn(SnapshotData.me)) { engine, plus, social in
                AddFriendSheet(friends: social.friends, squads: social.squads, plus: plus, avatar: engine.avatar, code: "NR4K7WQE", focusesField: false)
            })
        case "friends.added":
            return AnyView(PreviewModels(stats: SnapshotData.regular, account: .signedIn(SnapshotData.me)) { engine, plus, social in
                AddFriendSheet(
                    friends: social.friends,
                    squads: social.squads,
                    plus: plus,
                    avatar: engine.avatar,
                    added: .friend(SnapshotData.friends[1]),
                    focusesField: false
                )
            })

        // Squads (sheets, shown as screens)
        case "squads.list":
            // Friends, with a squad that's locked in right now at the top.
            return AnyView(PreviewModels(
                stats: SnapshotData.regular,
                account: .signedIn(SnapshotData.me),
                friends: SnapshotData.friends,
                squads: [SnapshotData.squad]
            ) { engine, plus, social in
                FriendsScreen(social: social, plus: plus, avatar: engine.avatar, onDone: {})
            })
        case "squads.new":
            return AnyView(PreviewModels(stats: SnapshotData.regular, account: .signedIn(SnapshotData.me), friends: SnapshotData.friends) { engine, plus, social in
                NewSquadSheet(squads: social.squads, plus: plus, avatar: engine.avatar, name: "Night Owls", focusesField: false) { _ in }
            })
        case "squads.detail":
            // The teen sprout, happy, six days running, and the week (M5).
            return AnyView(PreviewModels(
                stats: SnapshotData.regular,
                account: .signedIn(SnapshotData.me),
                friends: SnapshotData.friends,
                squads: [SnapshotData.squad],
                leaderboards: [SnapshotData.squad.id: SnapshotData.leaderboard]
            ) { engine, plus, social in
                NavigationStack {
                    SquadDetailScreen(
                        squads: social.squads,
                        friends: social.friends,
                        plus: plus,
                        avatar: engine.avatar,
                        squadID: SnapshotData.squad.id,
                        myID: SnapshotData.me.id,
                        invite: SnapshotData.squadCode
                    )
                }
            })
        case "squads.detail.boosted":
            // Squad Boost (M7): Sam has Plus, so the teen sprout wears the party hat; a freeze
            // saved the day before yesterday, and Sam has one left this month.
            return AnyView(PreviewModels(
                stats: SnapshotData.regular,
                isPlus: true,
                account: .signedIn(SnapshotData.me),
                friends: SnapshotData.friends,
                squads: [SnapshotData.boostedSquad(now: now)],
                leaderboards: [SnapshotData.squad.id: SnapshotData.leaderboard]
            ) { engine, plus, social in
                NavigationStack {
                    SquadDetailScreen(
                        squads: social.squads,
                        friends: social.friends,
                        plus: plus,
                        avatar: engine.avatar,
                        squadID: SnapshotData.squad.id,
                        myID: SnapshotData.me.id,
                        invite: SnapshotData.squadCode
                    )
                }
            })
        case "squads.review":
            // App Review's squad (docs/launch/app-review-notes.md §3): Demo Buddy, labelled as a
            // test bot, and the button that asks it to lock in.
            return AnyView(PreviewModels(
                stats: SnapshotData.regular,
                account: .signedIn(SnapshotData.me),
                squads: [SnapshotData.reviewSquad],
                leaderboards: [SnapshotData.reviewSquad.id: SnapshotData.reviewLeaderboard]
            ) { engine, plus, social in
                NavigationStack {
                    SquadDetailScreen(
                        squads: social.squads,
                        friends: social.friends,
                        plus: plus,
                        avatar: engine.avatar,
                        squadID: SnapshotData.reviewSquad.id,
                        myID: SnapshotData.me.id,
                        invite: SnapshotData.squadCode
                    )
                }
            })
        case "squads.detail.egg":
            // A new squad: its egg, tinted by what's inside, and nobody's focused yet this week.
            return AnyView(PreviewModels(
                stats: SnapshotData.regular,
                account: .signedIn(SnapshotData.me),
                friends: SnapshotData.friends,
                squads: [SnapshotData.eggSquad]
            ) { engine, plus, social in
                NavigationStack {
                    SquadDetailScreen(
                        squads: social.squads,
                        friends: social.friends,
                        plus: plus,
                        avatar: engine.avatar,
                        squadID: SnapshotData.eggSquad.id,
                        myID: SnapshotData.me.id,
                        invite: SnapshotData.squadCode
                    )
                }
            })
        case "squads.join":
            return AnyView(PreviewModels(stats: SnapshotData.regular, account: .signedIn(SnapshotData.me)) { engine, plus, social in
                AddFriendSheet(
                    friends: social.friends,
                    squads: social.squads,
                    plus: plus,
                    avatar: engine.avatar,
                    purpose: .squad,
                    code: SnapshotData.squadCode.code,
                    focusesField: false
                )
            })
        case "squads.joined":
            return AnyView(PreviewModels(stats: SnapshotData.regular, account: .signedIn(SnapshotData.me)) { engine, plus, social in
                AddFriendSheet(
                    friends: social.friends,
                    squads: social.squads,
                    plus: plus,
                    avatar: engine.avatar,
                    purpose: .squad,
                    added: .squad(SnapshotData.squad),
                    focusesField: false
                )
            })

        // Widgets and share cards (M6)
        case "widgets.pet":
            return AnyView(WidgetGalleryScreen(panel: .pet, avatar: SampleLocklings.you, now: now))
        case "widgets.lockin":
            return AnyView(WidgetGalleryScreen(panel: .lockIn, avatar: SampleLocklings.you, now: now))
        case "widgets.accessory":
            return AnyView(WidgetGalleryScreen(panel: .accessory, avatar: SampleLocklings.you, now: now))
        case "share.story":
            // The squad's card, as Stories gets it.
            return AnyView(ShareCardPreview(card: ShareSamples.squad, kind: .story))
        case "share.square":
            // Solo and signed out: no friend code yet.
            return AnyView(ShareCardPreview(card: ShareSamples.solo, kind: .square))

        // Developer tools
        case "developer":
            return AnyView(NavigationStack {
                DeveloperMenu()
                    .navigationDestination(for: AppRoute.self) { route in
                        route.destination
                    }
            })
        case "spike":
            // Before Start. The live screen asks ActivityKit for everything it shows.
            return AnyView(NavigationStack {
                APNsSpikeScreen(snapshot: .preStart)
            })
        case "lab.tokens":
            return AnyView(NavigationStack {
                DesignTokensScreen()
            })
        case "lab.liveactivity":
            return AnyView(NavigationStack {
                LiveActivityLabScreen(now: now)
            })
        case "lab.pets":
            return AnyView(NavigationStack {
                PetLabScreen()
            })
        default:
            // One part of a lab page, for when the whole page is taller than a screenshot:
            // lab.tokens.<part>, lab.liveactivity.<part>, lab.pets.<part>.
            if let part = suffix(of: route, after: "lab.tokens."), let panel = DesignTokensScreen.Panel(rawValue: part) {
                return AnyView(NavigationStack {
                    DesignTokensScreen(panels: [panel])
                })
            }
            if let part = suffix(of: route, after: "lab.liveactivity."), let panel = LiveActivityLabScreen.Panel(rawValue: part) {
                return AnyView(NavigationStack {
                    LiveActivityLabScreen(now: now, panels: [panel])
                })
            }
            if let part = suffix(of: route, after: "lab.pets."), let panel = PetLabScreen.Panel(rawValue: part) {
                return AnyView(NavigationStack {
                    PetLabScreen(panels: [panel])
                })
            }
            // The App Store screenshots (M6): store.1 to store.5.
            if let part = suffix(of: route, after: "store."), let shot = StoreShot(routePart: part) {
                return AnyView(StoreScreenshot(shot: shot, now: now))
            }
            return nil
        }
    }

    private static func onboarding(_ step: OnboardingFlow.Step, now: Date) -> AnyView {
        AnyView(PreviewModels(stats: SnapshotData.newcomer) { engine, plus, _ in
            OnboardingFlow(engine: engine, plus: plus, step: step, now: now, onFinish: {})
        })
    }

    private static func suffix(of route: String, after prefix: String) -> String? {
        route.hasPrefix(prefix) ? String(route.dropFirst(prefix.count)) : nil
    }
}

/// The made-up user the app screens are shot with. The App Store screenshots use it too.
@MainActor
enum SnapshotData {
    /// Before the first session.
    static var newcomer: FocusStats {
        FocusStats(todayMinutes: 0, streakDays: 0, coins: 0, completedSessions: 0)
    }

    /// Straight after the first session: the friends card shows.
    static var firstFinish: FocusStats {
        FocusStats(todayMinutes: 25, streakDays: 1, coins: 30, completedSessions: 1)
    }

    /// A few days in.
    static var regular: FocusStats {
        FocusStats(todayMinutes: 45, streakDays: 3, coins: 120, completedSessions: 7)
    }

    /// Sam's friend code.
    static var code: FriendCode {
        FriendCode(code: "KQ7M2XPA", url: URL(string: "https://lockin.example/j/KQ7M2XPA")!, expiresAt: 1_792_500_000)
    }

    /// The made-up user's account.
    static var me: User {
        User(id: "uSam000001", handle: "sam", displayName: "Sam", avatarCode: SampleLocklings.you.code, coins: 120, createdAt: 1_791_900_000)
    }

    /// The same account straight after Sign in with Apple: no handle yet.
    static var newAccount: User {
        User(id: "uSam000001", handle: nil, displayName: nil, avatarCode: SampleLocklings.you.code, createdAt: 1_791_900_000)
    }

    /// The pitch's three friends, as friends.
    static var friends: [Friend] {
        let handles = ["ava": "ava", "noor": "noor.k", "kai": "kai_lee"]
        return SampleLocklings.friends.map { sample in
            Friend(id: "u\(sample.id)", handle: handles[sample.id], displayName: sample.name, avatarCode: sample.avatar.code, since: 1_791_900_000)
        }
    }

    /// The squad's room on the server.
    static let squadSessionID = "r7Kq2xP9aL"

    /// Sam's squad with the pitch's three friends, locked in right now.
    static var squad: Squad {
        let members = [SquadMember(
            id: me.id,
            handle: me.handle,
            displayName: me.displayName,
            avatarCode: me.avatarCode,
            joinedAt: 1_791_900_000
        )] + friends.enumerated().map { index, friend in
            SquadMember(
                id: friend.id,
                handle: friend.handle,
                displayName: friend.displayName,
                avatarCode: friend.avatarCode,
                joinedAt: 1_791_900_000 + Double(index + 1) * 3_600
            )
        }
        return Squad(
            id: "sqLibGob01",
            name: "Library Goblins",
            ownerId: me.id,
            members: members,
            openSessionId: squadSessionID,
            muted: false,
            pet: SquadPet(species: "sprout", stage: 2, xp: 1_450, mood: PetMood.happy.rawValue),
            streak: SquadStreak(count: 6, countedToday: true, doneToday: 2, needed: 2),
            tz: "Europe/London"
        )
    }

    /// The same four the day the squad was made: an ember's egg, hungry, nobody focused yet.
    static var eggSquad: Squad {
        var egg = Self.squad
        egg.id = "sqNewEgg01"
        egg.name = "Night Owls"
        egg.openSessionId = nil
        egg.pet = SquadPet(species: "ember", stage: 0, xp: 0, mood: PetMood.hungry.rawValue)
        egg.streak = SquadStreak(count: 0, countedToday: false, doneToday: 0, needed: 2)
        return egg
    }

    /// The squad with Squad Boost on (M7): the teen sprout in its party hat, and a streak a freeze
    /// kept going the day before yesterday, with one of Sam's two left this month.
    static func boostedSquad(now: Date) -> Squad {
        var dressed = Self.squad
        dressed.openSessionId = nil
        dressed.boosted = true
        dressed.pet.accessory = PetAccessory.partyHat.rawValue
        let frozen = SquadStreak.day(of: now.addingTimeInterval(-2 * 86_400), in: dressed.timeZone)
        dressed.streak = SquadStreak(count: 6, countedToday: true, doneToday: 2, needed: 2, frozenDays: [frozen], freezes: 1)
        return dressed
    }

    /// Demo Buddy, the server's test bot (docs/launch/app-review-notes.md §3).
    static var demoBuddy: SquadMember {
        SquadMember(
            id: "DemoBuddy0",
            handle: "demobuddy",
            displayName: "Demo Buddy",
            avatarCode: "b2.c5.e4.h3",
            joinedAt: 1_791_900_060,
            isBot: true
        )
    }

    /// A Review Squad just made with the review code: Sam and Demo Buddy, and a fresh egg.
    static var reviewSquad: Squad {
        Squad(
            id: "sqReview01",
            name: "Review Squad",
            ownerId: me.id,
            members: [
                SquadMember(id: me.id, handle: me.handle, displayName: me.displayName, avatarCode: me.avatarCode, joinedAt: 1_791_900_000),
                demoBuddy,
            ],
            openSessionId: nil,
            muted: false,
            pet: SquadPet(species: "puff", stage: 0, xp: 0, mood: PetMood.hungry.rawValue),
            streak: SquadStreak(count: 0, countedToday: false, doneToday: 0, needed: 1),
            tz: "Europe/London"
        )
    }

    /// The Review Squad's week: Sam only, since Demo Buddy is never on a leaderboard.
    static var reviewLeaderboard: Leaderboard {
        Leaderboard(
            weekStart: "2026-10-12",
            startsAt: 1_791_759_600,
            endsAt: 1_792_364_400,
            entries: [Leaderboard.Entry(userId: me.id, minutes: 25, sessions: 1)]
        )
    }

    /// The squad's week: Noor ahead, Sam second.
    static var leaderboard: Leaderboard {
        let minutes = ["unoor": (310, 8), me.id: (245, 7), "uava": (180, 5), "ukai": (95, 3)]
        let order = ["unoor", me.id, "uava", "ukai"]
        return Leaderboard(
            weekStart: "2026-10-12",
            startsAt: 1_791_759_600,
            endsAt: 1_792_364_400,
            entries: order.map { id in
                Leaderboard.Entry(userId: id, minutes: minutes[id]?.0 ?? 0, sessions: minutes[id]?.1 ?? 0)
            }
        )
    }

    /// A finish that hatched the squad's egg: a baby sprout, happy, and Sam's 25 minutes of XP.
    static var hatch: SquadPetResult {
        SquadPetResult(
            squadName: squad.name,
            xp: 25,
            pet: PetCode(species: "sprout", stage: 1),
            mood: PetMood.happy.rawValue,
            hatched: true
        )
    }

    /// The squad's invite code.
    static var squadCode: FriendCode {
        FriendCode(code: "M4XQ7TRB", url: URL(string: "https://lockin.example/j/M4XQ7TRB")!, expiresAt: 1_792_500_000)
    }

    /// The squad's room ten minutes into Sam's 25: Ava focusing, Kai paused, Noor done.
    static func squadRoom(now: Date) -> SquadSessionInfo {
        let samples = SampleLocklings.friends
        let ava = friends[0]
        let noor = friends[1]
        let kai = friends[2]
        let members = [
            RoomMember(
                id: me.id, name: "Sam", avatar: SampleLocklings.you, state: .focusing,
                start: now.addingTimeInterval(-600), end: now.addingTimeInterval(900)
            ),
            RoomMember(
                id: ava.id, name: ava.name, avatar: samples[0].avatar, state: .focusing,
                start: now.addingTimeInterval(-1_500 + samples[0].secondsLeft), end: now.addingTimeInterval(samples[0].secondsLeft)
            ),
            RoomMember(
                id: kai.id, name: kai.name, avatar: samples[2].avatar, state: .paused,
                start: now.addingTimeInterval(-900), end: now.addingTimeInterval(600), pausedAt: now.addingTimeInterval(-120)
            ),
            RoomMember(
                id: noor.id, name: noor.name, avatar: samples[1].avatar, state: .done,
                start: now.addingTimeInterval(-1_600), end: now.addingTimeInterval(-100)
            ),
        ]
        return SquadSessionInfo(
            name: squad.name,
            room: LockinAttributes.ContentState(v: 12, m: members),
            me: me.id
        )
    }

    /// Ten minutes into 25, as the Live Activity samples are.
    static func running(now: Date) -> SessionEngine.Phase {
        .running(startedAt: now.addingTimeInterval(-600), endsAt: now.addingTimeInterval(900), plannedMinutes: 25)
    }

    /// Paused two minutes ago with 17 minutes to go.
    static func paused(now: Date) -> SessionEngine.Phase {
        .paused(
            startedAt: now.addingTimeInterval(-600),
            endsAt: now.addingTimeInterval(900),
            pausedAt: now.addingTimeInterval(-120),
            plannedMinutes: 25
        )
    }

    /// 25 minutes, done: 25 coins and 5 for finishing.
    static func finished(now: Date) -> SessionEngine.Phase {
        .finished(
            SessionRecord(
                id: "snapshot",
                startedAt: now.addingTimeInterval(-1_500),
                endedAt: now,
                plannedMinutes: 25,
                focusedSeconds: 1_500,
                completed: true,
                coinsEarned: 30
            )
        )
    }
}

/// Owns one shot's preview models, so a redraw never makes new ones.
struct PreviewModels<Content: View>: View {
    @StateObject private var engine: SessionEngine
    @StateObject private var plus: PlusStore
    @StateObject private var account: AccountStore
    @StateObject private var friends: FriendsStore
    @StateObject private var squads: SquadsStore
    @StateObject private var rooms: SquadRooms
    @StateObject private var shop: ShopStore
    private let content: (SessionEngine, PlusStore, SocialModels) -> Content

    /// - Parameters:
    ///   - account: signed out unless a shot says otherwise.
    ///   - isConfigured: false for a build without a server.
    ///   - coins: the shop's balance signed out (M5); the stats' coins unless said. Signed in,
    ///     it's the account's.
    ///   - owned: the shop items owned; what the sample Lockling wears unless said.
    init(
        phase: SessionEngine.Phase = .idle,
        stats: FocusStats,
        liveActivityProblem: LiveActivityError? = nil,
        isPlus: Bool = false,
        account: AccountStore.State = .signedOut,
        isConfigured: Bool = true,
        suggestedName: String? = nil,
        friends: [Friend] = [],
        squads: [Squad] = [],
        leaderboards: [String: Leaderboard] = [:],
        roomCounts: [String: Int] = [:],
        coins: Int? = nil,
        owned: [String]? = nil,
        @ViewBuilder content: @escaping (SessionEngine, PlusStore, SocialModels) -> Content
    ) {
        _engine = StateObject(wrappedValue: SessionEngine.preview(
            phase: phase,
            stats: stats,
            avatar: SampleLocklings.you,
            liveActivityProblem: liveActivityProblem
        ))
        _plus = StateObject(wrappedValue: PlusStore.preview(isPlus: isPlus))
        let accountStore = AccountStore.preview(account, isConfigured: isConfigured, suggestedName: suggestedName)
        _account = StateObject(wrappedValue: accountStore)
        _friends = StateObject(wrappedValue: FriendsStore.preview(
            account: accountStore,
            friends: friends,
            code: SnapshotData.code,
            redeems: SnapshotData.friends[1]
        ))
        _squads = StateObject(wrappedValue: SquadsStore.preview(squads: squads, leaderboards: leaderboards))
        _rooms = StateObject(wrappedValue: SquadRooms.preview(roomCounts))
        _shop = StateObject(wrappedValue: ShopStore.preview(
            account: accountStore,
            coins: coins ?? stats.coins,
            owned: owned ?? ShopCatalogue.freeItemIDs(wornBy: SampleLocklings.you)
        ))
        self.content = content
    }

    var body: some View {
        content(engine, plus, SocialModels(account: account, friends: friends, squads: squads, rooms: rooms, shop: shop))
    }
}

struct SnapshotHost: View {
    let mode: SnapshotMode
    @StateObject private var stepper = SnapshotStepper()

    var body: some View {
        let shot = mode.shots[min(stepper.index, mode.shots.count - 1)]
        Group {
            if let view = SnapshotGallery.view(for: shot.route, now: mode.referenceDate) {
                view
            } else {
                ContentUnavailableView(
                    "Unknown snapshot route",
                    systemImage: "questionmark.square.dashed",
                    description: Text(verbatim: shot.route)
                )
            }
        }
        // A fresh screen for every shot: no state carries over from the last one.
        .id(stepper.index)
        // The exporter waits for this marker before it captures, so it never photographs the
        // last screen while this one is still on its way (CI once caught nine stale shots in a
        // row). Invisible, and only ever in snapshot mode.
        .overlay(alignment: .topLeading) {
            Text(verbatim: String(stepper.index))
                .font(.system(size: 1))
                .foregroundStyle(.clear)
                .accessibilityIdentifier("lk.snapshot.\(stepper.index)")
        }
        .preferredColorScheme(shot.appearance?.colorScheme)
        .onAppear {
            // Screens settle at once, so a capture never catches one mid-transition.
            UIView.setAnimationsEnabled(false)
        }
    }
}

/// Steps to the next shot when the exporter says so (a Darwin notification, which crosses from
/// the test runner's process into the app's inside the simulator).
@MainActor
final class SnapshotStepper: ObservableObject {
    @Published private(set) var index = 0

    init() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterAddObserver(
            center,
            Unmanaged.passUnretained(self).toOpaque(),
            snapshotStepperNext,
            SnapshotMode.nextNotification as CFString,
            nil,
            .deliverImmediately
        )
    }

    fileprivate func advance() {
        index += 1
    }
}

/// The Darwin notification callback: a plain function, so it can be a C function pointer. It may
/// run on any thread, so it hops to the main actor before touching the stepper.
private func snapshotStepperNext(
    _ center: CFNotificationCenter?,
    _ observer: UnsafeMutableRawPointer?,
    _ name: CFNotificationName?,
    _ object: UnsafeRawPointer?,
    _ userInfo: CFDictionary?
) {
    guard let observer else { return }
    let stepper = Unmanaged<SnapshotStepper>.fromOpaque(observer).takeUnretainedValue()
    Task { @MainActor in stepper.advance() }
}

import Foundation
import Testing
import UserNotifications
@testable import Notifications

/// The "is locking in" alert exactly as the server sends it (docs/milestones/M4.md), read the way
/// iOS hands it to the app: parsed by Foundation, so dictionaries are `NSDictionary`.
private func serverPayload(_ json: String) throws -> [AnyHashable: Any] {
    let object = try JSONSerialization.jsonObject(with: Data(json.utf8))
    return try #require(object as? [AnyHashable: Any])
}

private let lockInJSON = """
{"aps":{"alert":{"title":"Library Goblins","body":"Ava is locking in 🔒"},"sound":"default",\
"category":"LK_LOCKIN","thread-id":"squad-Sq7Lb2Kd9P","interruption-level":"active"},\
"lk":{"type":"lockin","sid":"r7Kq2xP9aL","sq":"Sq7Lb2Kd9P"}}
"""

@Suite struct CategoryTests {
    @Test func identifiersMatchTheServer() {
        #expect(LockinNotificationCategory.identifier == "LK_LOCKIN")
        #expect(LockinNotificationCategory.join25 == "LK_JOIN_25")
        #expect(LockinNotificationCategory.join50 == "LK_JOIN_50")
    }

    @Test func joinButtonsOpenTheAppByDefault() {
        let category = LockinNotificationCategory.category()
        #expect(category.identifier == LockinNotificationCategory.identifier)
        #expect(category.actions.map(\.identifier) == [LockinNotificationCategory.join25, LockinNotificationCategory.join50])
        #expect(category.actions.map(\.title) == ["Join 25", "Join 50"])
        for action in category.actions {
            #expect(action.options.contains(.foreground))
            #expect(!action.options.contains(.destructive))
        }
    }

    @Test func theSpikeRunsThemInTheBackground() {
        let category = LockinNotificationCategory.category(joinsInBackground: true)
        #expect(category.actions.count == 2)
        for action in category.actions {
            #expect(!action.options.contains(.foreground))
            // Without unlocking: the spike's whole point.
            #expect(!action.options.contains(.authenticationRequired))
        }
    }

    @Test func everyCategoryIsRegistered() {
        let all = LockinNotificationCategory.all()
        #expect(all.map(\.identifier) == [LockinNotificationCategory.identifier])
    }

    @Test func buttonsStandForMinutes() {
        #expect(LockinNotificationCategory.minutes(forAction: LockinNotificationCategory.join25) == 25)
        #expect(LockinNotificationCategory.minutes(forAction: LockinNotificationCategory.join50) == 50)
        #expect(LockinNotificationCategory.minutes(forAction: UNNotificationDefaultActionIdentifier) == nil)
        #expect(LockinNotificationCategory.minutes(forAction: UNNotificationDismissActionIdentifier) == nil)
        #expect(LockinNotificationCategory.minutes(forAction: "LK_JOIN_90") == nil)
    }
}

@Suite struct LockInAlertTests {
    @Test func readsTheServersPayload() throws {
        let alert = LockInAlert(userInfo: try serverPayload(lockInJSON))
        #expect(alert == LockInAlert(sessionId: "r7Kq2xP9aL", squadId: "Sq7Lb2Kd9P"))
    }

    @Test func readsItsOwnPayload() {
        let alert = LockInAlert(sessionId: "r7Kq2xP9aL", squadId: "Sq7Lb2Kd9P")
        #expect(LockInAlert(userInfo: alert.userInfo) == alert)
    }

    @Test func extraKeysAreIgnored() throws {
        let json = #"{"aps":{},"lk":{"type":"lockin","sid":"r7Kq2xP9aL","sq":"Sq7Lb2Kd9P","v":2,"name":"Ava"},"other":1}"#
        #expect(LockInAlert(userInfo: try serverPayload(json))?.sessionId == "r7Kq2xP9aL")
    }

    @Test func aMissingTypeStillReads() throws {
        let json = #"{"lk":{"sid":"r7Kq2xP9aL","sq":"Sq7Lb2Kd9P"}}"#
        #expect(LockInAlert(userInfo: try serverPayload(json))?.squadId == "Sq7Lb2Kd9P")
    }

    @Test func anythingElseIsNotOne() throws {
        let payloads = [
            #"{"aps":{"alert":"Hello"}}"#,
            #"{"lk":"lockin"}"#,
            #"{"lk":{"type":"recap","sid":"r7Kq2xP9aL","sq":"Sq7Lb2Kd9P"}}"#,
            #"{"lk":{"type":7,"sid":"r7Kq2xP9aL","sq":"Sq7Lb2Kd9P"}}"#,
            #"{"lk":{"type":"lockin","sq":"Sq7Lb2Kd9P"}}"#,
            #"{"lk":{"type":"lockin","sid":"r7Kq2xP9aL"}}"#,
            #"{"lk":{"type":"lockin","sid":"","sq":"Sq7Lb2Kd9P"}}"#,
            #"{"lk":{"type":"lockin","sid":42,"sq":"Sq7Lb2Kd9P"}}"#,
            #"{"lk":{"type":"lockin","sid":null,"sq":"Sq7Lb2Kd9P"}}"#,
        ]
        for json in payloads {
            #expect(LockInAlert(userInfo: try serverPayload(json)) == nil, "\(json)")
        }
        #expect(LockInAlert(userInfo: [:]) == nil)
    }

    @Test func anOverlongIdIsRefused() {
        let long = String(repeating: "a", count: LockInAlert.maxIDLength + 1)
        let userInfo: [AnyHashable: Any] = ["lk": ["type": "lockin", "sid": long, "sq": "Sq7Lb2Kd9P"]]
        #expect(LockInAlert(userInfo: userInfo) == nil)
    }
}

@Suite struct RouteTests {
    @Test func joinButtonsJoinTheRoom() throws {
        let userInfo = try serverPayload(lockInJSON)
        #expect(NotificationRoute.route(actionIdentifier: LockinNotificationCategory.join25, userInfo: userInfo)
            == .join(sessionId: "r7Kq2xP9aL", squadId: "Sq7Lb2Kd9P", minutes: 25))
        #expect(NotificationRoute.route(actionIdentifier: LockinNotificationCategory.join50, userInfo: userInfo)
            == .join(sessionId: "r7Kq2xP9aL", squadId: "Sq7Lb2Kd9P", minutes: 50))
    }

    @Test func aTapOnTheAlertOpensTheSquad() throws {
        let route = NotificationRoute.route(actionIdentifier: UNNotificationDefaultActionIdentifier, userInfo: try serverPayload(lockInJSON))
        #expect(route == .openSquad(squadId: "Sq7Lb2Kd9P"))
        #expect(route.squadId == "Sq7Lb2Kd9P")
    }

    @Test func dismissingOrAnUnknownButtonDoesNothing() throws {
        let userInfo = try serverPayload(lockInJSON)
        #expect(NotificationRoute.route(actionIdentifier: UNNotificationDismissActionIdentifier, userInfo: userInfo) == .none)
        #expect(NotificationRoute.route(actionIdentifier: "LK_SNOOZE", userInfo: userInfo) == .none)
        #expect(NotificationRoute.none.squadId == nil)
    }

    @Test func otherAlertsAreLeftAlone() throws {
        let userInfo = try serverPayload(#"{"aps":{"alert":"Weekly recap"}}"#)
        #expect(NotificationRoute.route(actionIdentifier: UNNotificationDefaultActionIdentifier, userInfo: userInfo) == .none)
        #expect(NotificationRoute.route(actionIdentifier: LockinNotificationCategory.join25, userInfo: userInfo) == .none)
    }
}

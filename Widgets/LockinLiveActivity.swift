import ActivityKit
import DesignSystem
import LiveActivity
import Model
import SwiftUI
import WidgetKit

/// The Live Activity in every presentation. Only the system wiring lives here: the views come
/// from the LiveActivity module, so the app's Live Activity Lab draws exactly what this does
/// (docs/decisions/0001-live-activity-views-in-package.md).
struct LockinLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LockinAttributes.self) { context in
            // Lock Screen, the banner on iPhones without the island, StandBy, and the Watch's
            // Smart Stack (the view reads the activity family and fullscreen state itself).
            //
            // No activityBackgroundTint and no activitySystemActionForegroundColor: the system's
            // default background and button colours follow the phone's appearance and sit on the
            // wallpaper like Apple's own activities (design/SYSTEM.md). The view's text uses
            // hierarchical styles, so it stays vibrant on that background.
            LockScreenView(attributes: context.attributes, state: context.state)
                .widgetURL(Self.sessionURL(context.attributes.sid))
        } dynamicIsland: { context in
            // Apple's island template with the system's default margins: your Lockling and your
            // time either side of the camera, what you're doing under it, and along the bottom
            // either the session's buttons (solo) or your squadmates. The buttons are
            // `Button(intent:)`s inside the views; the system runs their intents in the app.
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ExpandedLeadingView(attributes: context.attributes, state: context.state)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ExpandedTrailingView(attributes: context.attributes, state: context.state)
                }
                DynamicIslandExpandedRegion(.center) {
                    ExpandedCenterView(attributes: context.attributes, state: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedBottomView(attributes: context.attributes, state: context.state)
                }
            } compactLeading: {
                CompactLeadingView(attributes: context.attributes, state: context.state)
            } compactTrailing: {
                CompactTrailingView(attributes: context.attributes, state: context.state)
            } minimal: {
                MinimalView(attributes: context.attributes, state: context.state)
            }
            // The tint. The island is always dark, and the system colour resolves to its dark
            // variant there by itself.
            .keylineTint(LKColor.tint)
            .widgetURL(Self.sessionURL(context.attributes.sid))
        }
        // The Apple Watch Smart Stack: LockScreenView draws its small layout there.
        .supplementalActivityFamilies([.small])
    }

    /// `lockin://session/<sid>`: opens the app on the session. The app reads it with `DeepLink`
    /// in `App/Sources/AppRoute.swift`; change both together.
    static func sessionURL(_ sid: String) -> URL? {
        var components = URLComponents()
        components.scheme = "lockin"
        components.host = "session"
        components.path = "/" + sid
        return components.url
    }
}

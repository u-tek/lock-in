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
            LockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(LKColor.liveActivityBackground)
                // The system's own buttons on the activity, readable on the night background
                // whatever the Lock Screen's appearance.
                .activitySystemActionForegroundColor(Self.ink)
                .widgetURL(Self.sessionURL(context.attributes.sid))
        } dynamicIsland: { context in
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
            .keylineTint(Self.keyline)
            .widgetURL(Self.sessionURL(context.attributes.sid))
        }
        // The Apple Watch Smart Stack: LockScreenView draws its small layout there.
        .supplementalActivityFamilies([.small])
    }

    // The activity is always drawn in the night appearance (`lkNightAppearance()`), so the
    // system-applied colours use the tokens' dark values rather than following the Lock Screen's
    // appearance.
    private static let ink = Color(rgb: LKPalette.textPrimary.dark)
    private static let keyline = Color(rgb: LKPalette.accent.dark)

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

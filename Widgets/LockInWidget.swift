import AppIntents
import LiveActivity
import Model
import SwiftUI
import WidgetKit
import WidgetViews

/// The Lock in widget (small): a button that starts a 25-minute solo session without opening the
/// app, and the session's countdown while it runs. The view and the button's intent come from
/// the packages; here is only the system wiring.
struct LockInWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.lockIn, provider: LockInProvider()) { entry in
            LockInEntryView(entry: entry)
        }
        .configurationDisplayName("Lock in")
        .description("Start a 25-minute session without opening Lockin, and watch it count down.")
        .supportedFamilies([.systemSmall])
    }
}

struct LockInEntry: TimelineEntry {
    let date: Date
    let data: WidgetData
}

/// An entry now, one when the session's time runs out (back to the button), and one at midnight
/// (today's minutes start again). The app reloads the timeline whenever a session starts, pauses
/// or ends.
struct LockInProvider: TimelineProvider {
    func placeholder(in context: Context) -> LockInEntry {
        LockInEntry(date: Date(), data: WidgetSamples.solo())
    }

    func getSnapshot(in context: Context, completion: @escaping (LockInEntry) -> Void) {
        let now = Date()
        let data = WidgetDataStore.appGroup().load() ?? WidgetSamples.solo(now: now)
        completion(LockInEntry(date: now, data: data.asSeen(at: now)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LockInEntry>) -> Void) {
        let now = Date()
        let stored = WidgetDataStore.appGroup().load() ?? .empty
        let entries = WidgetTimeline.entryDates(for: stored, from: now).map { date in
            LockInEntry(date: date, data: stored.asSeen(at: date))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct LockInEntryView: View {
    let entry: LockInEntry
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        // No widgetURL: a tap outside the button opens the app, which shows the session if one's
        // running.
        LockInWidgetView(data: entry.data, now: entry.date, isFullColor: renderingMode == .fullColor)
            .containerBackground(for: .widget) {
                WidgetSurface(accent: LockInWidgetView.accent)
            }
    }
}

/// Control Center (and the Lock Screen's and Action button's controls, iOS 18): "Lock in" starts a
/// 25-minute solo session with its Live Activity, through the same `StartSessionIntent` as the
/// widget's button.
struct LockInControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: WidgetKind.lockInControl) {
            ControlWidgetButton(action: StartSessionIntent()) {
                Label("Lock in", systemImage: "lock.fill")
            }
        }
        .displayName("Lock in")
        .description("Starts a 25-minute focus session.")
    }
}

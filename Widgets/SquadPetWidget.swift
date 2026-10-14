import AppIntents
import Model
import SwiftUI
import WidgetKit
import WidgetViews

/// The Squad pet widget: Home Screen small and medium, Lock Screen circular and rectangular. The
/// views come from the WidgetViews module, so the app's `widgets.pet` and `widgets.accessory`
/// snapshots draw exactly what this does; here is only the system wiring.
///
/// What it shows is what the app last wrote to the App Group (`WidgetDataStore`); the extension
/// has no network. The app reloads the timelines whenever that changes, and the timeline itself
/// moves on at midnight, when today's minutes and the pet's mood start again.
struct SquadPetWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: WidgetKind.squadPet,
            intent: SquadPetConfiguration.self,
            provider: SquadPetProvider()
        ) { entry in
            SquadPetEntryView(entry: entry)
        }
        .configurationDisplayName("Squad pet")
        .description("Your squad's pet and streak. With no squad yet, your Lockling and your own streak.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

struct SquadPetEntry: TimelineEntry {
    let date: Date
    let data: WidgetData
    /// The squad picked in the widget's settings; nil for the first.
    let squadID: String?
}

struct SquadPetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SquadPetEntry {
        SquadPetEntry(date: Date(), data: WidgetSamples.squads(), squadID: nil)
    }

    /// The widget gallery shows a squad's pet even before you have one: that's what the widget is
    /// for. On the Home Screen it's your own data.
    func snapshot(for configuration: SquadPetConfiguration, in context: Context) async -> SquadPetEntry {
        let now = Date()
        var data = (WidgetDataStore.appGroup().load() ?? .empty).asSeen(at: now)
        if context.isPreview, data.squads.isEmpty {
            data = WidgetSamples.squads(avatar: data.avatarCode, now: now)
        }
        return SquadPetEntry(date: now, data: data, squadID: configuration.squad?.id)
    }

    func timeline(for configuration: SquadPetConfiguration, in context: Context) async -> Timeline<SquadPetEntry> {
        let now = Date()
        let stored = WidgetDataStore.appGroup().load() ?? .empty
        let entries = WidgetTimeline.entryDates(for: stored, from: now).map { date in
            SquadPetEntry(date: date, data: stored.asSeen(at: date), squadID: configuration.squad?.id)
        }
        return Timeline(entries: entries, policy: .atEnd)
    }
}

struct SquadPetEntryView: View {
    let entry: SquadPetEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let content = PetWidgetContent(data: entry.data, squadID: entry.squadID)
        SquadPetWidgetView(content: content, family: family, isFullColor: renderingMode == .fullColor)
            .containerBackground(for: .widget) {
                switch family {
                case .accessoryCircular, .accessoryRectangular, .accessoryInline:
                    // The Lock Screen draws its own; the circular widget brings
                    // AccessoryWidgetBackground.
                    Color.clear
                default:
                    WidgetSurface(accent: content.accent)
                }
            }
            .widgetURL(content.url)
    }
}

// MARK: - Picking a squad

/// The widget's settings: which squad's pet to show.
struct SquadPetConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Squad pet" }
    static var description: IntentDescription { IntentDescription("Choose which squad's pet to show.") }

    /// Nil shows your first squad.
    @Parameter(title: "Squad")
    var squad: SquadEntity?

    init() {}
}

/// One of your squads, as the widget's settings list them: read from the widgets' data, so the
/// list is whatever the app last saw.
struct SquadEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Squad" }
    static var defaultQuery: SquadQuery { SquadQuery() }

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct SquadQuery: EntityQuery {
    func entities(for identifiers: [SquadEntity.ID]) async throws -> [SquadEntity] {
        Self.squads().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [SquadEntity] {
        Self.squads()
    }

    /// Your first squad, as the widget shows with nothing picked.
    func defaultResult() async -> SquadEntity? {
        Self.squads().first
    }

    private static func squads() -> [SquadEntity] {
        let squads = WidgetDataStore.appGroup().load()?.squads ?? []
        return squads.map { SquadEntity(id: $0.id, name: $0.name) }
    }
}

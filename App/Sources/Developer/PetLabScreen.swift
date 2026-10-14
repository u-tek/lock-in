import Creature
import DesignSystem
import Model
import SwiftUI

/// The squad pet in every species, stage and mood, drawn by the Creature module's `PetView`, so
/// the snapshots CI exports (`lab.pets`) are what the app and the Live Activity draw
/// (docs/milestones/M5.md). Each part is also a route of its own, `lab.pets.<part>`, for when the
/// whole page is taller than one screenshot.
///
/// The overview puts every pet on one screen at the smallest size that draws the detail. Each
/// species then gets a grid where the faces are easy to read, and its adult at the size the app
/// shows a squad's pet. The last part draws them at the Live Activity's size on what the system
/// draws behind it: the Lock Screen, the island's black and Always-On.
struct PetLabScreen: View {
    /// The page's parts, in order.
    enum Panel: String, CaseIterable, Identifiable {
        case overview
        case puff
        case sprout
        case ember
        case pebble
        case liveActivity = "liveactivity"

        var id: String { rawValue }
    }

    private let panels: [Panel]

    init(panels: [Panel] = Panel.allCases) {
        self.panels = panels
    }

    var body: some View {
        List {
            ForEach(panels) { panel in
                switch panel {
                case .overview: OverviewSection()
                case .puff: SpeciesSection(species: .puff)
                case .sprout: SpeciesSection(species: .sprout)
                case .ember: SpeciesSection(species: .ember)
                case .pebble: SpeciesSection(species: .pebble)
                case .liveActivity: LiveActivitySection()
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Pet Lab")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// What the Lab draws, and what it calls it.
private enum PetLab {
    /// Egg, baby, teen, adult and the first prestige form.
    static let stages = Array(0...4)

    /// The smallest size `PetView` draws its detail at (cheeks, highlights, the flower).
    static let detailedSize: CGFloat = 28
    /// The Live Activity's pet row (`ActivityMetrics.petRowCreature`).
    static let petRowSize: CGFloat = 18

    static func code(_ species: PetSpecies, _ stage: Int) -> PetCode {
        PetCode(species: species.rawValue, stage: stage)
    }

    /// "Egg", "Teen", "Prestige".
    static func stageTitle(_ stage: Int) -> String {
        capitalised(PetCode(stage: stage).stageName)
    }

    /// "Sad", "Hungry", "Content", "Happy".
    static func moodTitle(_ mood: PetMood) -> String {
        capitalised(mood.name)
    }

    /// How each species grows, for its section's footer.
    static func summary(of species: PetSpecies) -> String {
        switch species {
        case .puff:
            "A little cloud. More puffs as it grows, and an adult trails a wisp of its own."
        case .sprout:
            "A seed with a sprout on top: two leaves as a baby, a third as a teen, four and a flower as an adult."
        case .ember:
            "A friendly flame with a bright heart where its face is: one tip as a baby, two as a teen, three as an adult."
        case .pebble:
            "A smooth river stone: plain as a baby, an amethyst crystal as a teen, a cluster of them as an adult."
        }
    }

    private static func capitalised(_ text: String) -> String {
        text.prefix(1).uppercased() + String(text.dropFirst())
    }
}

// MARK: - Overview

/// Every species at every stage, each as a square of its four moods.
private struct OverviewSection: View {
    var body: some View {
        Section {
            Grid(alignment: .center, horizontalSpacing: LKSpacing.s, verticalSpacing: LKSpacing.m) {
                GridRow {
                    Color.clear
                        .gridCellUnsizedAxes([.horizontal, .vertical])
                    ForEach(PetSpecies.allCases, id: \.self) { species in
                        Text(species.title)
                            .font(LKFont.caption.weight(.semibold))
                            .foregroundStyle(LKColor.textSecondary)
                            .lineLimit(1)
                    }
                }
                ForEach(PetLab.stages, id: \.self) { stage in
                    GridRow {
                        StageLabel(stage: stage)
                        ForEach(PetSpecies.allCases, id: \.self) { species in
                            MoodSquare(code: PetLab.code(species, stage), size: PetLab.detailedSize)
                        }
                    }
                }
            }
            .padding(.vertical, LKSpacing.s)
            .frame(maxWidth: .infinity)
            .listRowInsets(EdgeInsets(top: 0, leading: LKSpacing.s, bottom: 0, trailing: LKSpacing.s))
        } header: {
            Text("Every pet")
        } footer: {
            Text("Each square is one species at one stage in its four moods: sad and hungry above, content and happy below. The egg shows its mood by leaning; the prestige form is the adult in a halo.")
        }
    }
}

/// One species at one stage in its four moods: sad and hungry above, content and happy below.
private struct MoodSquare: View {
    let code: PetCode
    let size: CGFloat

    var body: some View {
        Grid(horizontalSpacing: LKSpacing.xxs, verticalSpacing: LKSpacing.xxs) {
            GridRow {
                PetView(code: code, mood: PetMood.sad.rawValue, size: size)
                PetView(code: code, mood: PetMood.hungry.rawValue, size: size)
            }
            GridRow {
                PetView(code: code, mood: PetMood.content.rawValue, size: size)
                PetView(code: code, mood: PetMood.happy.rawValue, size: size)
            }
        }
    }
}

// MARK: - One species

/// One species: every stage down, every mood across, then the adult at the size the app shows a
/// squad's pet.
private struct SpeciesSection: View {
    let species: PetSpecies

    private static let gridSize: CGFloat = 56
    private static let heroSize: CGFloat = 160

    var body: some View {
        Section {
            Grid(alignment: .center, horizontalSpacing: LKSpacing.s, verticalSpacing: LKSpacing.s) {
                GridRow {
                    Color.clear
                        .gridCellUnsizedAxes([.horizontal, .vertical])
                    ForEach(PetMood.allCases, id: \.self) { mood in
                        MoodLabel(mood: mood)
                    }
                }
                ForEach(PetLab.stages, id: \.self) { stage in
                    GridRow {
                        StageLabel(stage: stage)
                        ForEach(PetMood.allCases, id: \.self) { mood in
                            PetView(code: PetLab.code(species, stage), mood: mood.rawValue, size: Self.gridSize)
                        }
                    }
                }
            }
            .padding(.vertical, LKSpacing.s)
            .frame(maxWidth: .infinity)
            .listRowInsets(EdgeInsets(top: 0, leading: LKSpacing.s, bottom: 0, trailing: LKSpacing.s))

            PetView(code: PetLab.code(species, 3), mood: PetMood.happy.rawValue, size: Self.heroSize)
                .padding(.vertical, LKSpacing.s)
                .frame(maxWidth: .infinity)
        } header: {
            Text(species.title)
        } footer: {
            Text(PetLab.summary(of: species))
        }
    }
}

/// A mood's name over its column, beside a dot in its colour (design/SYSTEM.md, "Pet mood").
private struct MoodLabel: View {
    let mood: PetMood

    var body: some View {
        HStack(spacing: LKSpacing.xs) {
            Circle()
                .fill(LKColor.petMood(mood.rawValue))
                .frame(width: 6, height: 6)
            Text(PetLab.moodTitle(mood))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .font(LKFont.caption.weight(.semibold))
        .foregroundStyle(LKColor.textSecondary)
    }
}

/// A stage's name at the start of its row.
private struct StageLabel: View {
    let stage: Int

    var body: some View {
        Text(PetLab.stageTitle(stage))
            .font(LKFont.caption)
            .foregroundStyle(LKColor.textSecondary)
            .lineLimit(1)
            .fixedSize()
            .gridColumnAlignment(.leading)
    }
}

// MARK: - Live Activity

/// The pets at the Live Activity's pet row size, on stand-ins for what the system draws behind
/// them (`ActivityFrames.swift`): the Lock Screen's card, the island's black, and Always-On,
/// where the pet is an outline with a light face.
private struct LiveActivitySection: View {
    var body: some View {
        Section {
            Text("Lock Screen")
            SmallPets()
                .padding(LKSpacing.m)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: LKRadius.card, style: .continuous))
                .activityStageRow(.wallpaper)
            Text("Dynamic Island")
            SmallPets()
                .padding(LKSpacing.m)
                .background(LKColor.islandBackground, in: RoundedRectangle(cornerRadius: LKRadius.card, style: .continuous))
                // The island is always dark, so system colours take their dark variants there.
                .environment(\.colorScheme, .dark)
                .activityStageRow(.wallpaper)
            Text("Always-On")
            SmallPets()
                .padding(LKSpacing.m)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: LKRadius.card, style: .continuous))
                .environment(\.isLuminanceReduced, true)
                .environment(\.colorScheme, .dark)
                .activityStageRow(.dimmedWallpaper)
        } header: {
            Text("Live Activity")
        } footer: {
            Text("18 points, the pet row on the Lock Screen and in StandBy. On the left every stage, content; on the right every mood, as a teen. Below 28 points the pet keeps its shape and face and drops the small things.")
        }
    }
}

/// Each species in a row: every stage in a content mood, then every mood as a teen.
private struct SmallPets: View {
    var body: some View {
        HStack(alignment: .top, spacing: LKSpacing.l) {
            Grid(horizontalSpacing: LKSpacing.s, verticalSpacing: LKSpacing.s) {
                ForEach(PetSpecies.allCases, id: \.self) { species in
                    GridRow {
                        ForEach(PetLab.stages, id: \.self) { stage in
                            PetView(code: PetLab.code(species, stage), mood: PetMood.content.rawValue, size: PetLab.petRowSize)
                        }
                    }
                }
            }
            Grid(horizontalSpacing: LKSpacing.s, verticalSpacing: LKSpacing.s) {
                ForEach(PetSpecies.allCases, id: \.self) { species in
                    GridRow {
                        ForEach(PetMood.allCases, id: \.self) { mood in
                            PetView(code: PetLab.code(species, 2), mood: mood.rawValue, size: PetLab.petRowSize)
                        }
                    }
                }
            }
        }
    }
}

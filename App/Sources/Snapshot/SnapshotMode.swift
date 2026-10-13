import DesignSystem
import SwiftUI
import UIKit

/// Shows screens in a fixed state for the UI snapshot exporter (`UITests/SnapshotExportTests`).
///
/// Launch argument: `-LKSnapshots home@light,home@dark,spike@dark,...`. The app shows the first,
/// then steps to the next each time the exporter posts the `next` Darwin notification, so one
/// launch covers every screen. Arguments in this form land in the `UserDefaults` argument domain,
/// so they never persist.
///
/// Nothing in snapshot mode touches ActivityKit or the App Group: the spike screen gets a fixed
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
        let appearance: Appearance
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
            let appearance = parts.count > 1 ? Appearance(rawValue: parts[1]) ?? .dark : .dark
            return Shot(route: route, appearance: appearance)
        }
        return shots.isEmpty ? nil : SnapshotMode(shots: shots, referenceDate: Date())
    }()
}

/// Every screen the exporter can open, by route name. `scripts/snapshot-routes.txt` lists the
/// ones CI exports; `lab.*` routes render on the iPhone 16 Pro only.
@MainActor
enum SnapshotGallery {
    static func view(for route: String, now: Date) -> AnyView? {
        switch route {
        case "home":
            return AnyView(NavigationStack {
                HomeScreen(showsDeveloperTools: true, previewDate: now)
                    .navigationDestination(for: AppRoute.self) { route in
                        route.destination
                    }
            })
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
        default:
            // One part of a lab page, for when the whole page is taller than a screenshot:
            // lab.tokens.<part>, lab.liveactivity.<part>.
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
            return nil
        }
    }

    private static func suffix(of route: String, after prefix: String) -> String? {
        route.hasPrefix(prefix) ? String(route.dropFirst(prefix.count)) : nil
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
                Text(verbatim: "Unknown snapshot route \(shot.route)")
                    .font(LKFont.body)
                    .foregroundStyle(LKColor.textPrimary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .lkScreenBackground()
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
        .preferredColorScheme(shot.appearance.colorScheme)
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

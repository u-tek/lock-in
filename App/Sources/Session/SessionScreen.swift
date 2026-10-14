import Creature
import DesignSystem
import LiveActivity
import Model
import SessionEngine
import SwiftUI
import UIKit

/// The session: your Lockling hard at work inside a ring that fills as the time runs, a big
/// countdown, and Pause and End. The countdown is `Text(timerInterval:)`, so it ticks by itself.
///
/// In a squad session your squadmates sit in a row above, each with their own countdown. Tap one
/// to cheer them on; a cheer sent to you pops up over your Lockling.
struct SessionScreen: View {
    @ObservedObject var engine: SessionEngine
    let clock: SessionClock
    /// The room, in a squad session; nil when solo.
    let squad: SquadSessionInfo?

    @State private var confirmsEnd = false
    /// What ending now would pay, worked out when End is tapped.
    @State private var coinsSoFar = 0
    /// The squadmate whose cheer picker is open.
    @State private var cheering: String?
    /// A cheer for you, on screen for a moment.
    @State private var landing: RoomCheer?
    @State private var cheersSent = 0
    @State private var cheerFailure: String? = nil
    @Environment(\.openURL) private var openURL

    /// - Parameter cheering: a squadmate whose cheer picker is open to start with (snapshots).
    init(engine: SessionEngine, clock: SessionClock, squad: SquadSessionInfo? = nil, cheering: String? = nil) {
        self.engine = engine
        self.clock = clock
        self.squad = squad
        _cheering = State(initialValue: cheering)
    }

    private var tone: LKMemberTone {
        clock.isPaused ? .paused : .focusing
    }

    /// The squadmate whose picker is open, while they're still in the room.
    private var cheeringMember: RoomMember? {
        guard let cheering, let squad else { return nil }
        return squad.others.first { $0.i == cheering && $0.state != .left }
    }

    var body: some View {
        GeometryReader { proxy in
            // Smaller in a squad, to leave room for the squadmates' row.
            let share = squad == nil ? 0.4 : 0.32
            let ring = min(proxy.size.width - 2 * LKSpacing.xxl, proxy.size.height * share, 300)
            VStack(spacing: 0) {
                if let squad {
                    notice
                    squadHeader(squad)
                } else {
                    notice
                        .frame(minHeight: 44)
                }
                Spacer(minLength: LKSpacing.m)
                ZStack {
                    ProgressRing(clock: clock, tint: tone.color)
                    CreatureView(avatar: engine.avatar, pose: clock.isPaused ? .paused : .focusing, size: ring * 0.58)
                }
                .frame(width: ring, height: ring)
                .overlay(alignment: .top) {
                    if let landing {
                        FloatingCheer(kind: CheerKind(kind: landing.k), from: squad?.member(id: landing.f)?.n)
                            .padding(.top, ring * 0.02)
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                }
                .accessibilityHidden(true)
                Spacer(minLength: LKSpacing.m)
                status
                countdown
                Spacer(minLength: LKSpacing.l)
                controls
            }
            .padding(.horizontal, LKSpacing.xl)
            .padding(.bottom, LKSpacing.l)
            .frame(width: proxy.size.width, height: proxy.size.height)
            .overlayPreferenceValue(SquadRowBounds.self) { bounds in
                CheerPickerLayer(rowBounds: bounds, member: cheeringMember, onCheer: send) {
                    withAnimation(LKMotion.press) {
                        cheering = nil
                    }
                }
            }
        }
        .background {
            LinearGradient(colors: [tone.color.opacity(0.22), tone.color.opacity(0)], startPoint: .top, endPoint: .center)
                .background(Color(uiColor: .systemBackground))
                .ignoresSafeArea()
        }
        .sensoryFeedback(.impact(weight: .light), trigger: cheersSent)
        // When a cheer lands, not when it goes.
        .sensoryFeedback(.success, trigger: landing?.at) { _, arrived in
            arrived != nil
        }
        .errorAlert("Couldn't send that cheer", message: $cheerFailure)
        .onChange(of: squad?.cheerForMe, initial: true) { _, cheer in
            receive(cheer)
        }
    }

    // MARK: - Squad

    /// The squad's name over everyone else's Lockling and timer.
    private func squadHeader(_ squad: SquadSessionInfo) -> some View {
        VStack(spacing: LKSpacing.m) {
            if let name = squad.name {
                Label(name, systemImage: "person.3.fill")
                    .font(LKFont.footnote.weight(.semibold))
                    .foregroundStyle(LKColor.textSecondary)
                    .lineLimit(1)
            }
            SquadmatesRow(members: squad.others, cheer: squad.room.c, selection: cheering) { member in
                withAnimation(LKMotion.press) {
                    cheering = cheering == member.i ? nil : member.i
                }
            }
            .anchorPreference(key: SquadRowBounds.self, value: .bounds) { $0 }
        }
        .padding(.top, LKSpacing.s)
    }

    private func send(_ kind: CheerKind, to member: RoomMember) {
        withAnimation(LKMotion.press) {
            cheering = nil
        }
        cheersSent += 1
        Task {
            do {
                try await engine.cheer(memberId: member.i, kind: kind.rawValue)
            } catch is CancellationError {
                return
            } catch {
                cheerFailure = error.squadMessage
            }
        }
    }

    /// A cheer for you that's just arrived pops up for a moment. One the room is still holding
    /// from a while ago (the server keeps it about 10 seconds) stays quiet.
    private func receive(_ cheer: RoomCheer?) {
        guard let cheer, cheer != landing, Date().timeIntervalSince1970 - cheer.at < 15 else { return }
        withAnimation(LKMotion.celebrate) {
            landing = cheer
        }
        let from = squad?.member(id: cheer.f)?.n ?? "Your squad"
        UIAccessibility.post(notification: .announcement, argument: "\(from) cheered you on")
        Task {
            try? await Task.sleep(for: .seconds(2.6))
            if landing == cheer {
                withAnimation(LKMotion.settle) {
                    landing = nil
                }
            }
        }
    }

    // MARK: - Parts

    /// Live Activities switched off beats the first-time hint: the hint would be wrong. A squad
    /// session has its squad up there instead of the hint.
    @ViewBuilder
    private var notice: some View {
        if engine.liveActivityProblem == .disabled {
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            } label: {
                Label("Turn on Live Activities", systemImage: "exclamationmark.circle.fill")
                    .font(LKFont.footnote.weight(.semibold))
            }
            .lkSecondaryButton()
            .controlSize(.small)
            .tint(.orange)
        } else if squad == nil, engine.stats.completedSessions == 0 {
            Label("Lock your phone — your Lockling is on the Lock Screen.", systemImage: "lock.iphone")
                .font(LKFont.footnote.weight(.medium))
                .foregroundStyle(LKColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .padding(.vertical, LKSpacing.s)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: LKRadius.medium, style: .continuous))
        }
    }

    private var status: some View {
        Label(clock.isPaused ? "Paused" : "Locked in", systemImage: tone.symbolName)
            .font(LKFont.headline)
            .foregroundStyle(tone.color)
            .contentTransition(.symbolEffect(.replace))
    }

    private var countdown: some View {
        Text(timerInterval: clock.timerRange, pauseTime: clock.pausedAt, countsDown: true)
            .font(LKFont.timerApp)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .foregroundStyle(clock.isPaused ? AnyShapeStyle(LKColor.textSecondary) : AnyShapeStyle(LKColor.textPrimary))
    }

    private var controls: some View {
        HStack(alignment: .top, spacing: 56) {
            RoundControl(
                title: clock.isPaused ? "Resume" : "Pause",
                symbol: clock.isPaused ? "play.fill" : "pause.fill"
            ) {
                if clock.isPaused {
                    engine.resume()
                } else {
                    engine.pause()
                }
            }
            RoundControl(title: "End", symbol: "xmark", role: .destructive) {
                coinsSoFar = clock.focusedMinutes(at: Date())
                confirmsEnd = true
            }
            .confirmationDialog("End early?", isPresented: $confirmsEnd, titleVisibility: .visible) {
                Button("End session", role: .destructive) {
                    engine.end()
                }
                Button("Keep going", role: .cancel) {}
            } message: {
                Text(endMessage)
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: clock.isPaused)
    }

    private var endMessage: String {
        let coins = switch coinsSoFar {
        case 0: "You haven't earned any coins yet."
        case 1: "You'll keep 1 coin."
        default: "You'll keep \(coinsSoFar) coins."
        }
        // Gently social (SPEC.md §1.4): the squad sees it, nothing worse.
        return squad == nil ? coins : "Your squad will see you've left. \(coins)"
    }
}

/// A thin ring that fills as the session runs. Redrawn each second; frozen while paused.
private struct ProgressRing: View {
    let clock: SessionClock
    let tint: Color

    private static let lineWidth: CGFloat = 6

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let progress = clock.progress(at: context.date)
            ZStack {
                Circle()
                    .stroke(tint.opacity(0.16), lineWidth: Self.lineWidth)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(tint, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .padding(Self.lineWidth / 2)
    }
}

/// A round button with its name under it, like Clock's timer buttons.
private struct RoundControl: View {
    let title: String
    let symbol: String
    var role: ButtonRole?
    let action: () -> Void

    init(title: String, symbol: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.role = role
        self.action = action
    }

    var body: some View {
        VStack(spacing: LKSpacing.s) {
            Button(role: role, action: action) {
                Image(systemName: symbol)
                    .font(.title2.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonBorderShape(.circle)
            .lkSecondaryButton()
            .controlSize(.large)
            .accessibilityLabel(title)
            Text(title)
                .font(LKFont.footnote.weight(.medium))
                .foregroundStyle(LKColor.textSecondary)
                .accessibilityHidden(true)
        }
    }
}

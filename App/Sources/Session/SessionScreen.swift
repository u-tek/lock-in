import Creature
import DesignSystem
import LiveActivity
import SessionEngine
import SwiftUI
import UIKit

/// The session: your Lockling hard at work inside a ring that fills as the time runs, a big
/// countdown, and Pause and End. The countdown is `Text(timerInterval:)`, so it ticks by itself.
struct SessionScreen: View {
    @ObservedObject var engine: SessionEngine
    let clock: SessionClock

    @State private var confirmsEnd = false
    /// What ending now would pay, worked out when End is tapped.
    @State private var coinsSoFar = 0
    @Environment(\.openURL) private var openURL

    private var tone: LKMemberTone {
        clock.isPaused ? .paused : .focusing
    }

    var body: some View {
        GeometryReader { proxy in
            let ring = min(proxy.size.width - 2 * LKSpacing.xxl, proxy.size.height * 0.4, 300)
            VStack(spacing: 0) {
                notice
                    .frame(minHeight: 44)
                Spacer(minLength: LKSpacing.m)
                ZStack {
                    ProgressRing(clock: clock, tint: tone.color)
                    CreatureView(avatar: engine.avatar, pose: clock.isPaused ? .paused : .focusing, size: ring * 0.58)
                }
                .frame(width: ring, height: ring)
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
        }
        .background {
            LinearGradient(colors: [tone.color.opacity(0.22), tone.color.opacity(0)], startPoint: .top, endPoint: .center)
                .background(Color(uiColor: .systemBackground))
                .ignoresSafeArea()
        }
    }

    // MARK: - Parts

    /// Live Activities switched off beats the first-time hint: the hint would be wrong.
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
        } else if engine.stats.completedSessions == 0 {
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
        switch coinsSoFar {
        case 0: "You haven't earned any coins yet."
        case 1: "You'll keep 1 coin."
        default: "You'll keep \(coinsSoFar) coins."
        }
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

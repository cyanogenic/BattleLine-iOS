import SwiftUI

/// The first app-rendered frame matches LaunchScreen.storyboard exactly.
/// The nine lines indicate activity, not a percentage of work completed.
struct LaunchLoadingView: View {
    let onAnimationFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var showsActivity = false
    @State private var animationStart = Date()

    var body: some View {
        Group {
            if showsActivity && !reduceMotion && scenePhase == .active {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                    let elapsed = context.date.timeIntervalSince(animationStart)
                    artwork(phase: elapsed.truncatingRemainder(dividingBy: 1.0) / 1.0)
                }
            } else {
                artwork(phase: nil)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BattleLineTheme.background)
        .ignoresSafeArea()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("正在准备对局")
        .task(id: scenePhase) {
            // Time the visible presentation from an active scene, not model
            // initialization: fast local reads must not skip the animation.
            guard scenePhase == .active else { return }
            animationStart = .now
            withAnimation(.easeIn(duration: 0.12)) {
                showsActivity = true
            }
            do {
                // Reduced Motion uses static artwork and a shorter transition.
                try await Task.sleep(for: .milliseconds(reduceMotion ? 250 : 1200))
                try Task.checkCancellation()
                onAnimationFinished()
            } catch {
                // If backgrounded, resume the visible presentation when active.
            }
        }
    }

    private func artwork(phase: Double?) -> some View {
        Image("BattleLineLogo")
            .resizable()
            .scaledToFit()
            // Keep size and full-screen centering in sync with the storyboard.
            .frame(width: 180, height: 180)
            .shadow(
                color: BattleLineTheme.gold.opacity(
                    phase.map { 0.10 + 0.04 * sin($0 * 2 * .pi) } ?? 0
                ),
                radius: 10
            )
            .overlay(alignment: .bottom) {
                if showsActivity {
                    HStack(spacing: 5) {
                        ForEach(0..<9) { index in
                            Capsule()
                                .fill(BattleLineTheme.gold.opacity(brightness(index, phase: phase)))
                                .frame(width: 12, height: 3)
                        }
                    }
                    .offset(y: 30)
                    .transition(.opacity)
                }
            }
    }

    private func brightness(_ index: Int, phase: Double?) -> Double {
        guard let phase else { return 0.45 }
        // The light crosses all nine lines and fades beyond either end.
        let distance = abs(Double(index) - (phase * 12 - 2))
        return 0.22 + 0.78 * max(0, 1 - distance / 2)
    }
}

#Preview("Loading") {
    LaunchLoadingView(onAnimationFinished: {})
}


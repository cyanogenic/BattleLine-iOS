import SwiftUI

@main
struct BattleLineApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            AppRootView(model: model)
                .preferredColorScheme(nil)
        }
    }
}

private struct AppRootView: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            BattleLineTheme.background
                .ignoresSafeArea()

            if !model.isShowingLaunch {
                screenContent
                    .transition(.opacity)
            } else {
                LaunchLoadingView(onAnimationFinished: model.finishLaunchAnimation)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.isShowingLaunch)
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: model.screen)
        .task { await model.prepareForLaunch() }
    }

    @ViewBuilder
    private var screenContent: some View {
        switch model.screen {
        case .home:
            HomeView(
                createMatch: model.showHostSetup,
                joinMatch: model.showJoinLobby,
                hasResumableMatch: model.hasResumableSession,
                continueMatch: model.continueMatch,
                abandonMatch: model.abandonMatch
            )
        case .hostSetup:
            HostSetupView(
                setup: $model.setup,
                cancel: model.showHome,
                create: model.createNearbyMatch
            )
        case .hostLobby:
            HostLobbyView(
                coordinator: model.nearby,
                cancel: model.showHome
            )
        case .joinLobby:
            JoinLobbyView(
                coordinator: model.nearby,
                cancel: model.showHome
            )
        case .match:
            MatchView(
                model: model.match,
                leaveMatch: model.leaveMatch
            )
        }
    }
}

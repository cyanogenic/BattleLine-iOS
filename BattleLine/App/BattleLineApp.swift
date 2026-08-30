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

    var body: some View {
        ZStack {
            BattleLineTheme.background
                .ignoresSafeArea()

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
        .animation(.snappy(duration: 0.28), value: model.screen)
    }
}

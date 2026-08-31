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
                Group {
                    if model.needsNickname {
                        NicknameEditorView(
                            isFirstLaunch: true,
                            initialNickname: "",
                            save: model.profile.saveNickname
                        )
                    } else {
                        screenContent
                    }
                }
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
                abandonMatch: model.abandonMatch,
                openSettings: model.showSettings
            )
        case .settings:
            SettingsView(
                nickname: model.profile.nickname,
                back: model.showHome,
                showPersonalInfo: model.showPersonalInfo
            )
        case .personalInfo:
            NicknameEditorView(
                isFirstLaunch: false,
                initialNickname: model.profile.nickname,
                cancel: model.showSettings,
                save: { nickname in
                    guard model.profile.saveNickname(nickname) else { return false }
                    model.showSettings()
                    return true
                }
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

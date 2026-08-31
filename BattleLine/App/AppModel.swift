import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    enum Screen: Hashable {
        case home
        case settings
        case personalInfo
        case hostSetup
        case hostLobby
        case joinLobby
        case match
    }

    private(set) var isReady = false
    private(set) var hasFinishedLaunchAnimation = false

    var isShowingLaunch: Bool {
        !isReady || !hasFinishedLaunchAnimation
    }
    @ObservationIgnored private var startupTask: Task<Void, Never>?

    var screen: Screen = .home
    var setup = MatchSetupDraft()
    let profile: PlayerProfile
    @ObservationIgnored private var bypassesNicknameSetup = false

    var needsNickname: Bool {
        profile.nickname.isEmpty && !bypassesNicknameSetup
    }
    let match: MatchViewModel
    let nearby: NearbyMatchCoordinator

    init(
        persistence: NearbyMatchPersistence = NearbyMatchPersistence(),
        profile: PlayerProfile = PlayerProfile(),
        transportFactory: @escaping NearbyMatchCoordinator.TransportFactory = {
            BLENearbyTransport(role: $0)
        }
    ) {
        self.profile = profile
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        let showsClaimPreview = arguments.contains("--preview-claim")
        let showsMatchPreview = arguments.contains("--preview-match") || showsClaimPreview
        let match = showsMatchPreview ? MatchViewModel.preview() : MatchViewModel()
        if showsClaimPreview {
            match.phase = .claiming
            for index in match.lines.indices {
                match.lines[index].isClaimable = true
            }
            match.selectedClaimIDs = [3, 5]
        }
        #else
        let match = MatchViewModel()
        #endif
        self.match = match
        nearby = NearbyMatchCoordinator(
            matchModel: match, transportFactory: transportFactory, persistence: persistence
        )
        nearby.onMatchReady = { [weak self] in
            self?.screen = .match
        }
        #if DEBUG
        if showsMatchPreview {
            bypassesNicknameSetup = true
            isReady = true
            hasFinishedLaunchAnimation = true
            screen = .match
        }
        #endif
    }

    /// Shared across view task restarts; restoring once prevents an old save from
    /// replacing a session the player has already resumed or abandoned.
    func prepareForLaunch() async {
        guard !isReady else { return }
        if startupTask == nil {
            startupTask = Task { [nearby] in
                #if DEBUG
                // Exercise the loading UI without slowing down normal launches.
                if ProcessInfo.processInfo.arguments.contains("--preview-launch") {
                    try? await Task.sleep(for: .seconds(6))
                }
                #endif
                await nearby.restorePersistedSession()
            }
        }
        await startupTask?.value
        guard !Task.isCancelled else { return }
        isReady = true
        startupTask = nil
    }

    func finishLaunchAnimation() {
        hasFinishedLaunchAnimation = true
    }

    var hasResumableSession: Bool {
        nearby.canResumeCurrentSession
    }

    func showHome() {
        nearby.pauseAndReturnHome()
        screen = .home
    }

    func cancelLobby() {
        nearby.abandonCurrentSession()
        screen = .home
    }

    func showSettings() {
        guard !needsNickname else { return }
        screen = .settings
    }

    func showPersonalInfo() {
        screen = .personalInfo
    }

    func showHostSetup() {
        guard !needsNickname, !hasResumableSession else { return }
        setup = MatchSetupDraft(playerName: profile.nickname)
        screen = .hostSetup
    }

    func showJoinLobby() {
        guard !needsNickname, !hasResumableSession else { return }
        nearby.startJoining(playerName: profile.nickname)
        screen = .joinLobby
    }

    func createNearbyMatch() {
        guard !needsNickname, !hasResumableSession else { return }
        setup.playerName = profile.nickname
        nearby.startHosting(setup: setup)
        screen = .hostLobby
    }

    func continueMatch() {
        guard !needsNickname else { return }
        guard nearby.resumeCurrentSession() != nil else { return }
        screen = .match
    }

    func abandonMatch() {
        nearby.abandonCurrentSession()
    }

    func leaveMatch() {
        nearby.pauseAndReturnHome()
        screen = .home
    }
}

struct MatchSetupDraft: Codable, Equatable, Sendable {
    var playerName = "房主"
    var advancedClaiming = false
}

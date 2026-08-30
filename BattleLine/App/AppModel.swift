import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    enum Screen: Hashable {
        case home
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
    var joiningPlayerName = "加入者"
    let match: MatchViewModel
    let nearby: NearbyMatchCoordinator

    init(persistence: NearbyMatchPersistence = NearbyMatchPersistence()) {
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
        nearby = NearbyMatchCoordinator(matchModel: match, persistence: persistence)
        nearby.onMatchReady = { [weak self] in
            self?.screen = .match
        }
        #if DEBUG
        if showsMatchPreview {
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

    func showHostSetup() {
        guard !hasResumableSession else { return }
        setup = MatchSetupDraft()
        screen = .hostSetup
    }

    func showJoinLobby() {
        guard !hasResumableSession else { return }
        nearby.startJoining(playerName: joiningPlayerName)
        screen = .joinLobby
    }

    func createNearbyMatch() {
        nearby.startHosting(setup: setup)
        screen = .hostLobby
    }

    func continueMatch() {
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

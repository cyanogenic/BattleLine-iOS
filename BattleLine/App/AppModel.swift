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

    var screen: Screen = .home {
        didSet {
            if screen != oldValue { feedbackPlayer.stop() }
        }
    }
    var setup = MatchSetupDraft()
    let profile: PlayerProfile
    let feedbackSettings: FeedbackSettings
    @ObservationIgnored private let feedbackPlayer: any TurnFeedbackPlaying
    @ObservationIgnored private var isAppActive = false
    @ObservationIgnored private var bypassesNicknameSetup = false

    var needsNickname: Bool {
        profile.nickname.isEmpty && !bypassesNicknameSetup
    }
    let match: MatchViewModel
    let nearby: NearbyMatchCoordinator

    init(
        persistence: NearbyMatchPersistence = NearbyMatchPersistence(),
        profile: PlayerProfile = PlayerProfile(),
        feedbackSettings: FeedbackSettings = FeedbackSettings(),
        feedbackPlayer: any TurnFeedbackPlaying = TurnFeedbackPlayer(),
        transportFactory: @escaping NearbyMatchCoordinator.TransportFactory = {
            BLENearbyTransport(role: $0)
        }
    ) {
        self.profile = profile
        self.feedbackSettings = feedbackSettings
        self.feedbackPlayer = feedbackPlayer
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
        nearby.onLocalTurnStarted = { [weak self] in
            self?.playTurnReminder()
        }
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

    func setAppActive(_ active: Bool) {
        isAppActive = active
        if !active { feedbackPlayer.stop() }
    }

    /// Called by the settings toggle, not while loading saved preferences.
    func setHapticsEnabled(_ enabled: Bool) {
        let wasEnabled = feedbackSettings.hapticsEnabled
        feedbackSettings.hapticsEnabled = enabled
        guard enabled else {
            feedbackPlayer.stop()
            return
        }
        guard !wasEnabled, isAppActive, screen == .settings, !isShowingLaunch else { return }
        feedbackPlayer.play(soundEnabled: false, hapticsEnabled: true)
    }

    private func playTurnReminder() {
        guard isAppActive, screen == .match, !isShowingLaunch,
              feedbackSettings.soundEnabled || feedbackSettings.hapticsEnabled
        else { return }
        feedbackPlayer.play(
            soundEnabled: feedbackSettings.soundEnabled,
            hapticsEnabled: feedbackSettings.hapticsEnabled
        )
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

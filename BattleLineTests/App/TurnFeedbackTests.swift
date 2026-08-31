import AVFAudio
import Foundation
import Testing
@testable import BattleLine

@Suite("Turn feedback preferences and lifecycle")
@MainActor
struct TurnFeedbackTests {
    @Test("Preferences default on and each independent combination survives restart",
          arguments: [false, true], [false, true])
    func preferencesAndPlayback(sound: Bool, haptics: Bool) async throws {
        let fixture = try FeedbackFixture()
        defer { fixture.cleanUp() }
        let settings = FeedbackSettings(defaults: fixture.defaults)
        #expect(settings.soundEnabled)
        #expect(settings.hapticsEnabled)
        settings.soundEnabled = sound
        settings.hapticsEnabled = haptics
        let reopened = FeedbackSettings(defaults: fixture.defaults)
        #expect(reopened.soundEnabled == sound)
        #expect(reopened.hapticsEnabled == haptics)

        let player = FeedbackSpy()
        let model = fixture.makeModel(settings: reopened, player: player)
        await model.prepareForLaunch()
        model.finishLaunchAnimation()
        model.screen = .match
        model.setAppActive(true)
        model.nearby.onLocalTurnStarted?()
        #expect(player.requests == (sound || haptics
            ? [.init(sound: sound, haptics: haptics)] : []))

        // Reading the live preference model at the next event makes changes
        // effective without recreating the app or the current match.
        reopened.soundEnabled.toggle()
        reopened.hapticsEnabled.toggle()
        player.requests = []
        model.nearby.onLocalTurnStarted?()
        #expect(player.requests == (!sound || !haptics
            ? [.init(sound: !sound, haptics: !haptics)] : []))
    }

    @Test("Inactive and off-board events are discarded, and leaving cancels feedback")
    func lifecycleDoesNotReplayOldEvents() async throws {
        let fixture = try FeedbackFixture()
        defer { fixture.cleanUp() }
        let player = FeedbackSpy()
        let model = fixture.makeModel(player: player)
        model.screen = .match
        model.setAppActive(true)
        model.nearby.onLocalTurnStarted?()
        #expect(player.requests.isEmpty) // Launch is still covering the board.
        await model.prepareForLaunch()
        model.finishLaunchAnimation()

        model.setAppActive(false)
        let stopsAfterInactive = player.stopCount
        #expect(stopsAfterInactive > 0)
        model.nearby.onLocalTurnStarted?()
        model.setAppActive(true)
        #expect(player.requests.isEmpty)
        model.nearby.onLocalTurnStarted?()
        #expect(player.requests.count == 1)

        model.screen = .settings
        #expect(player.stopCount == stopsAfterInactive + 1)
        model.nearby.onLocalTurnStarted?()
        model.screen = .match
        #expect(player.requests.count == 1)
        model.nearby.onLocalTurnStarted?()
        #expect(player.requests.count == 2)
        let stopsBeforeRepeatedMatch = player.stopCount
        model.screen = .match // Repeated match-ready callbacks must not cut off feedback.
        #expect(player.stopCount == stopsBeforeRepeatedMatch)
        model.setAppActive(false)
        #expect(player.stopCount == stopsBeforeRepeatedMatch + 1)
    }

    @Test("Enabling haptics in settings previews once without sound", arguments: [false, true])
    func settingsTogglePreviewsHaptics(soundEnabled: Bool) async throws {
        let fixture = try FeedbackFixture()
        defer { fixture.cleanUp() }
        let player = FeedbackSpy()
        let model = fixture.makeModel(player: player)
        await model.prepareForLaunch()
        model.finishLaunchAnimation()
        model.feedbackSettings.soundEnabled = soundEnabled
        model.setAppActive(true)
        model.screen = .settings
        #expect(player.requests.isEmpty)
        model.setHapticsEnabled(true)
        #expect(player.requests.isEmpty) // Loading an already-enabled preference is silent.

        model.setHapticsEnabled(false)
        #expect(player.requests.isEmpty)
        #expect(!FeedbackSettings(defaults: fixture.defaults).hapticsEnabled)
        model.setHapticsEnabled(true)
        #expect(player.requests == [.init(sound: false, haptics: true)])
        #expect(FeedbackSettings(defaults: fixture.defaults).hapticsEnabled)
        model.setHapticsEnabled(true)
        #expect(player.requests.count == 1)

        // Turning the switch off during the long pulse cancels the remaining preview.
        let stopsBeforeDisable = player.stopCount
        model.setHapticsEnabled(false)
        #expect(player.stopCount == stopsBeforeDisable + 1)
        #expect(player.requests.count == 1)
        model.setHapticsEnabled(true)
        #expect(player.requests == Array(repeating: .init(sound: false, haptics: true), count: 2))

        // Leaving settings cancels even if the next screen is the match screen.
        let stopsBeforeLeaving = player.stopCount
        model.screen = .match
        #expect(player.stopCount == stopsBeforeLeaving + 1)
        model.screen = .settings
        #expect(player.requests.count == 2)
    }

    @Test("Launch, inactive, and non-settings changes do not preview or queue haptics")
    func settingsPreviewRequiresVisibleActiveSettings() async throws {
        let fixture = try FeedbackFixture()
        defer { fixture.cleanUp() }
        let player = FeedbackSpy()
        let model = fixture.makeModel(player: player)
        model.setAppActive(true)
        model.screen = .settings
        model.setHapticsEnabled(false)
        model.setHapticsEnabled(true)
        #expect(player.requests.isEmpty)
        await model.prepareForLaunch()
        model.finishLaunchAnimation()
        #expect(player.requests.isEmpty)

        model.setAppActive(false)
        model.setHapticsEnabled(false)
        model.setHapticsEnabled(true)
        model.setAppActive(true)
        #expect(player.requests.isEmpty)
        for screen in [AppModel.Screen.home, .match] {
            model.screen = screen
            model.setHapticsEnabled(false)
            model.setHapticsEnabled(true)
        }
        model.screen = .settings
        #expect(player.requests.isEmpty)
        model.setHapticsEnabled(false)
        model.setHapticsEnabled(true)
        #expect(player.requests == [.init(sound: false, haptics: true)])
        let stopsBeforeBackground = player.stopCount
        model.setAppActive(false)
        #expect(player.stopCount == stopsBeforeBackground + 1)
        model.setAppActive(true)
        #expect(player.requests.count == 1)
    }

    @Test("Missing or invalid stored preferences use enabled defaults")
    func invalidStoredPreferences() throws {
        let fixture = try FeedbackFixture()
        defer { fixture.cleanUp() }
        fixture.defaults.set("invalid", forKey: FeedbackSettings.soundKey)
        fixture.defaults.set(["invalid"], forKey: FeedbackSettings.hapticsKey)
        let settings = FeedbackSettings(defaults: fixture.defaults)
        #expect(settings.soundEnabled)
        #expect(settings.hapticsEnabled)
    }

    @Test("The built app includes a playable short reminder sound")
    func bundledSound() throws {
        let url = try #require(Bundle.main.url(forResource: "turn-reminder", withExtension: "wav"))
        let file = try AVAudioFile(forReading: url)
        let duration = Double(file.length) / file.processingFormat.sampleRate
        #expect(duration >= 0.3 && duration < 1)
        #expect(file.processingFormat.channelCount == 1)
    }
}

@MainActor
private final class FeedbackSpy: TurnFeedbackPlaying {
    struct Request: Equatable {
        let sound: Bool
        let haptics: Bool
    }
    var requests: [Request] = []
    var stopCount = 0

    func play(soundEnabled: Bool, hapticsEnabled: Bool) {
        requests.append(Request(sound: soundEnabled, haptics: hapticsEnabled))
    }

    func stop() { stopCount += 1 }
}

@MainActor
private struct FeedbackFixture {
    let suite = "BattleLineFeedbackTests-\(UUID().uuidString)"
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "BattleLineFeedbackTests-\(UUID().uuidString)")
    let defaults: UserDefaults

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suite))
    }

    func makeModel(settings: FeedbackSettings? = nil, player: FeedbackSpy) -> AppModel {
        AppModel(
            persistence: NearbyMatchPersistence(fileURL: directory.appending(path: "match.json")),
            profile: PlayerProfile(defaults: defaults),
            feedbackSettings: settings ?? FeedbackSettings(defaults: defaults),
            feedbackPlayer: player
        )
    }

    func cleanUp() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }
}

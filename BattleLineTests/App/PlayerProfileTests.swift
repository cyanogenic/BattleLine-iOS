import BattleLineCore
import Foundation
import Testing
@testable import BattleLine

@Suite("Player nickname")
@MainActor
struct PlayerProfileTests {
    @Test("Spaces, emoji clusters, and international names are preserved", arguments: [
        "小 明 🎮", "👨‍👩‍👧‍👦", "👍🏽", "🇨🇳", "Café", "محمد", "小明的 iPhone",
        String(repeating: "👨‍👩‍👧‍👦", count: 20)
    ])
    func acceptsNickname(_ name: String) {
        #expect(NicknameRules.validationMessage(for: name) == nil)
    }

    @Test("Blank, oversized, and hidden control inputs are rejected", arguments: [
        "", "   ", "\n", "小\n明", "小\t明", "\t小明", "小明\r", "A\u{0000}B",
        "A\u{202E}B", "A\u{2066}B", "\u{200D}", "\u{FE0F}", "\u{0301}", "\u{3164}", "\u{2800}",
        String(repeating: "名", count: 21),
        "A" + String(repeating: "\u{0301}", count: 600)
    ])
    func rejectsNickname(_ name: String) {
        #expect(NicknameRules.validationMessage(for: name) != nil)
    }

    @Test("First launch requires a name; saving survives model recreation")
    func onboardingAndPersistence() async throws {
        let fixture = try ProfileFixture()
        defer { fixture.cleanUp() }
        let model = fixture.makeModel()
        await model.prepareForLaunch()
        model.finishLaunchAnimation()
        #expect(!model.isShowingLaunch)
        #expect(model.needsNickname)
        model.showHostSetup()
        model.showJoinLobby()
        model.createNearbyMatch()
        #expect(model.screen == .home)
        #expect(model.nearby.role == nil)

        #expect(model.profile.saveNickname("  小 明 👨‍👩‍👧‍👦  "))
        #expect(!model.needsNickname)
        #expect(model.profile.nickname == "小 明 👨‍👩‍👧‍👦")
        let reopened = fixture.makeModel()
        #expect(!reopened.needsNickname)
        #expect(reopened.profile.nickname == "小 明 👨‍👩‍👧‍👦")
        #expect(!reopened.profile.saveNickname("  "))
        #expect(fixture.makeModel().profile.nickname == "小 明 👨‍👩‍👧‍👦")

        model.showHostSetup()
        #expect(model.setup.playerName == "小 明 👨‍👩‍👧‍👦")
        model.createNearbyMatch()
        #expect(model.nearby.localPlayerName == "小 明 👨‍👩‍👧‍👦")
        model.cancelLobby()
        model.showJoinLobby()
        #expect(model.nearby.localPlayerName == "小 明 👨‍👩‍👧‍👦")
        model.cancelLobby()
    }

    @Test("Corrupt profile values require onboarding instead of leaking into a match")
    func invalidSavedProfile() throws {
        let fixture = try ProfileFixture()
        defer { fixture.cleanUp() }
        fixture.defaults.set("A\u{202E}B", forKey: PlayerProfile.nicknameKey)
        #expect(fixture.makeModel().needsNickname)
        fixture.defaults.set(42, forKey: PlayerProfile.nicknameKey)
        #expect(fixture.makeModel().needsNickname)
    }

    @Test("Renaming preserves unfinished matches across restart and resume", arguments: [false, true])
    func renamePreservesSavedSession(guest: Bool) async throws {
        let fixture = try ProfileFixture()
        defer { fixture.cleanUp() }
        let game = BattleLineGame(configuration: .init(), dealer: .playerOne, seed: 123)
        let seat: PlayerID = guest ? .playerTwo : .playerOne
        let saved = PersistedNearbyMatch(
            role: guest ? .guest : .host, matchID: UUID(), resumeToken: UUID(), localSeat: seat,
            localPlayerName: "旧昵称", opponentName: "对手", pairingCode: "123 456",
            advancedClaiming: false, game: guest ? nil : game,
            guestView: guest ? game.view(for: seat) : nil,
            guestClaimableFlagIndices: [], processedCommandIDs: []
        )
        try fixture.persistence.save(saved)
        let model = fixture.makeModel()
        await model.prepareForLaunch()
        #expect(model.needsNickname)
        #expect(model.hasResumableSession)
        #expect(model.profile.saveNickname("个人昵称"))
        model.showSettings()
        model.showPersonalInfo()
        #expect(model.screen == .personalInfo)
        #expect(model.profile.saveNickname("新 昵称 🎮"))
        #expect(model.nearby.localPlayerName == "旧昵称")
        #expect(model.match.localPlayerName == "旧昵称")
        #expect(fixture.persistence.load()?.localPlayerName == "旧昵称")
        #expect(fixture.persistence.load()?.matchID == saved.matchID)

        let reopened = fixture.makeModel()
        await reopened.prepareForLaunch()
        #expect(!reopened.needsNickname)
        #expect(reopened.profile.nickname == "新 昵称 🎮")
        reopened.continueMatch()
        #expect(reopened.screen == .match)
        #expect(reopened.nearby.localPlayerName == "旧昵称")
        #expect(reopened.match.localPlayerName == "旧昵称")
        reopened.abandonMatch()
        reopened.showHostSetup()
        #expect(reopened.setup.playerName == "新 昵称 🎮")
        reopened.createNearbyMatch()
        #expect(reopened.nearby.localPlayerName == "新 昵称 🎮")
        reopened.cancelLobby()
        reopened.showJoinLobby()
        #expect(reopened.nearby.localPlayerName == "新 昵称 🎮")
        reopened.cancelLobby()
    }
}

@MainActor
private struct ProfileFixture {
    let suite = "BattleLineProfileTests-\(UUID().uuidString)"
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "BattleLineProfileTests-\(UUID().uuidString)")
    let defaults: UserDefaults
    let persistence: NearbyMatchPersistence

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suite))
        persistence = NearbyMatchPersistence(fileURL: directory.appending(path: "match.json"))
    }

    func makeModel() -> AppModel {
        AppModel(persistence: persistence, profile: PlayerProfile(defaults: defaults)) {
            ProfileTestTransport(role: $0)
        }
    }

    func cleanUp() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor
private final class ProfileTestTransport: NearbyTransport {
    let role: BLENearbyRole
    var state: NearbyConnectionState = .idle
    let events: AsyncStream<NearbyTransportEvent>
    private let continuation: AsyncStream<NearbyTransportEvent>.Continuation

    init(role: BLENearbyRole) {
        self.role = role
        (events, continuation) = AsyncStream.makeStream()
    }

    func start() { state = role == .host ? .advertising : .scanning }
    func stop() { state = .stopped; continuation.finish() }
    func send(_ payload: Data) async throws { throw NearbyTransportError.notConnected }
}

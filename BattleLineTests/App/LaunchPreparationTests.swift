import BattleLineCore
import Foundation
import Testing
@testable import BattleLine

@Suite("Launch preparation")
@MainActor
struct LaunchPreparationTests {
    @Test("Fast preparation cannot skip the visible launch animation")
    func fastPreparationKeepsLaunchVisible() async {
        let file = FileManager.default.temporaryDirectory
            .appending(path: "BattleLineMissingSave-\(UUID().uuidString).json")
        let model = AppModel(persistence: NearbyMatchPersistence(fileURL: file))
        #expect(model.isShowingLaunch)
        await model.prepareForLaunch()
        #expect(model.isReady)
        #expect(model.isShowingLaunch)
        model.finishLaunchAnimation()
        #expect(!model.isShowingLaunch)
        // A repeated view task or foreground return must not replay the intro.
        await model.prepareForLaunch()
        #expect(!model.isShowingLaunch)
    }

    @Test("Finishing the animation cannot expose home before data is ready")
    func animationWaitsForPreparation() async {
        let file = FileManager.default.temporaryDirectory
            .appending(path: "BattleLineMissingSave-\(UUID().uuidString).json")
        let model = AppModel(persistence: NearbyMatchPersistence(fileURL: file))
        model.finishLaunchAnimation()
        #expect(model.isShowingLaunch)
        await model.prepareForLaunch()
        #expect(!model.isShowingLaunch)
    }

    @Test("Missing or corrupt saves still allow the home screen", arguments: [false, true])
    func missingOrCorruptSave(corrupt: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "BattleLineLaunchTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "match.json")
        if corrupt {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("invalid save".utf8).write(to: file)
        }
        let model = AppModel(persistence: NearbyMatchPersistence(fileURL: file))
        #expect(!model.isReady)
        await model.prepareForLaunch()
        #expect(model.isReady)
        #expect(model.screen == .home)
        #expect(!model.hasResumableSession)
    }

    @Test("Launch restores each seat without connecting Bluetooth", arguments: [false, true])
    func restoreSavedSession(guest: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "BattleLineLaunchTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = NearbyMatchPersistence(fileURL: directory.appending(path: "match.json"))
        let game = BattleLineGame(
            configuration: .init(claimingRule: .advancedClaiming),
            dealer: .playerTwo,
            seed: 42
        )
        let seat: PlayerID = guest ? .playerTwo : .playerOne
        let saved = PersistedNearbyMatch(
            role: guest ? .guest : .host,
            matchID: UUID(), resumeToken: UUID(), localSeat: seat,
            localPlayerName: "本机玩家", opponentName: "对手", pairingCode: "123 456",
            advancedClaiming: true,
            game: guest ? nil : game,
            guestView: guest ? game.view(for: seat) : nil,
            guestClaimableFlagIndices: [], processedCommandIDs: []
        )
        try persistence.save(saved)
        let model = AppModel(persistence: persistence)
        // Constructing the model no longer reads disk or restores the session.
        #expect(!model.hasResumableSession)
        async let first: Void = model.prepareForLaunch()
        async let second: Void = model.prepareForLaunch()
        _ = await (first, second)
        #expect(model.isReady)
        #expect(model.screen == .home)
        #expect(model.hasResumableSession)
        #expect(model.nearby.stage == .idle)
        #expect(model.nearby.role == saved.role)
        #expect(model.match.localPlayerName == "本机玩家")
        #expect(model.match.hand.count == 7)
        #expect(model.match.deckCount == 46)
        #expect(Set(model.match.hand.map(\.id)) == Set(game.hand(for: seat).map {
            "\($0.color.rawValue)-\($0.value)"
        }))
        if case .paused = model.match.phase {} else {
            Issue.record("Restored match should wait for the player to resume")
        }

        model.abandonMatch()
        // A later view task must not read a stale save and resurrect an abandoned match.
        try persistence.save(saved)
        await model.prepareForLaunch()
        #expect(!model.hasResumableSession)
    }
}

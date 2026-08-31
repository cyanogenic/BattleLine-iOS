import BattleLineCore
import Foundation
import Testing
@testable import BattleLine

@Suite("Turn reminder tracker")
@MainActor
struct TurnReminderTrackerTests {
    @Test("Recovery consumes missed turns without replaying them or losing the next live turn",
          arguments: PlayerID.allCases)
    func recoveryConsumesMissedTurns(viewer: PlayerID) throws {
        let matchID = UUID()
        var game = makeGame(startingPlayer: viewer.opponent)
        var tracker = TurnReminderTracker()
        let beforeDisconnect = game.view(for: viewer)
        let shouldRemind1 = tracker.consume(beforeDisconnect, matchID: matchID, isLive: true)
        #expect(!shouldRemind1)

        // The first recovery snapshot can be newer than the last state seen on
        // this device. Suppress all missed transitions while adopting its state.
        for _ in 0 ..< 3 { try completeTurn(in: &game) }
        let recovered = game.view(for: viewer)
        #expect(recovered.currentPlayer == viewer)
        #expect(recovered.turn > beforeDisconnect.turn)
        let shouldRemind2 = tracker.consume(recovered, matchID: matchID, isLive: false)
        #expect(!shouldRemind2)
        let shouldRemind3 = tracker.consume(recovered, matchID: matchID, isLive: true)
        #expect(!shouldRemind3)
        let shouldRemind4 = tracker.consume(beforeDisconnect, matchID: matchID, isLive: true)
        #expect(!shouldRemind4)
        let shouldRemind5 = tracker.consume(recovered, matchID: matchID, isLive: true)
        #expect(!shouldRemind5)

        try completeTurn(in: &game)
        let opponentsNextTurn = game.view(for: viewer)
        let shouldRemind6 = tracker.consume(opponentsNextTurn, matchID: matchID, isLive: true)
        #expect(!shouldRemind6)
        try completeTurn(in: &game)
        let nextLiveTurn = game.view(for: viewer)
        let shouldRemind7 = tracker.consume(nextLiveTurn, matchID: matchID, isLive: true)
        #expect(shouldRemind7)
        let shouldRemind8 = tracker.consume(nextLiveTurn, matchID: matchID, isLive: true)
        #expect(!shouldRemind8)
        let shouldRemind9 = tracker.consume(opponentsNextTurn, matchID: matchID, isLive: true)
        #expect(!shouldRemind9)
        let shouldRemind10 = tracker.consume(nextLiveTurn, matchID: matchID, isLive: true)
        #expect(!shouldRemind10)
    }

    @Test("A first snapshot never announces a local turn, including a late first snapshot",
          arguments: PlayerID.allCases)
    func firstLocalSnapshotOnlyEstablishesBaseline(viewer: PlayerID) throws {
        let matchID = UUID()
        var game = makeGame(startingPlayer: viewer)
        var tracker = TurnReminderTracker()
        let shouldRemind11 = tracker.consume(game.view(for: viewer), matchID: matchID, isLive: true)
        #expect(!shouldRemind11)

        try completeTurn(in: &game)
        try completeTurn(in: &game)
        var lateTracker = TurnReminderTracker()
        #expect(game.currentPlayer == viewer)
        let lateShouldRemind = lateTracker.consume(
            game.view(for: viewer), matchID: matchID, isLive: true
        )
        #expect(!lateShouldRemind)
    }

    @Test("A different match and an explicit reset both require a fresh baseline")
    func matchIdentityAndResetRequireBaseline() throws {
        var game = makeGame(startingPlayer: .playerTwo)
        var tracker = TurnReminderTracker()
        let shouldRemind12 = tracker.consume(game.view(for: .playerOne), matchID: UUID(), isLive: true)
        #expect(!shouldRemind12)

        try completeTurn(in: &game)
        let replacementMatchID = UUID()
        let localTurn = game.view(for: .playerOne)
        // This would be an opponent-to-local transition if match identity were ignored.
        let shouldRemind13 = tracker.consume(localTurn, matchID: replacementMatchID, isLive: true)
        #expect(!shouldRemind13)
        tracker.reset()
        let shouldRemind14 = tracker.consume(localTurn, matchID: replacementMatchID, isLive: true)
        #expect(!shouldRemind14)

        // The reset also permits a fresh game whose version and turn are lower.
        tracker.reset()
        game = makeGame(startingPlayer: .playerOne)
        let shouldRemind15 = tracker.consume(game.view(for: .playerOne), matchID: replacementMatchID, isLive: true)
        #expect(!shouldRemind15)
        try completeTurn(in: &game)
        let shouldRemind16 = tracker.consume(game.view(for: .playerOne), matchID: replacementMatchID, isLive: true)
        #expect(!shouldRemind16)
        try completeTurn(in: &game)
        let shouldRemind17 = tracker.consume(game.view(for: .playerOne), matchID: replacementMatchID, isLive: true)
        #expect(shouldRemind17)
    }

    @Test("Changing the viewer establishes a new baseline before tracking that seat")
    func viewerChangeRequiresBaseline() throws {
        let matchID = UUID()
        var game = makeGame(startingPlayer: .playerOne)
        var tracker = TurnReminderTracker()
        let shouldRemind18 = tracker.consume(game.view(for: .playerOne), matchID: matchID, isLive: true)
        #expect(!shouldRemind18)

        try completeTurn(in: &game)
        let shouldRemind19 = tracker.consume(game.view(for: .playerTwo), matchID: matchID, isLive: true)
        #expect(!shouldRemind19)
        try completeTurn(in: &game)
        let shouldRemind20 = tracker.consume(game.view(for: .playerTwo), matchID: matchID, isLive: true)
        #expect(!shouldRemind20)
        try completeTurn(in: &game)
        let shouldRemind21 = tracker.consume(game.view(for: .playerTwo), matchID: matchID, isLive: true)
        #expect(shouldRemind21)
    }

    @Test("Winner and game-over signals each suppress a would-be turn reminder",
          arguments: CompletionSignal.allCases)
    func finishedViewsNeverAnnounceTurns(signal: CompletionSignal) throws {
        let matchID = UUID()
        var game = makeGame(startingPlayer: .playerTwo)
        var tracker = TurnReminderTracker()
        let shouldRemind22 = tracker.consume(game.view(for: .playerOne), matchID: matchID, isLive: true)
        #expect(!shouldRemind22)
        try completeTurn(in: &game)

        // Public views are immutable; encode a terminal fixture without giving
        // the app tests access to, or modifying, the rules engine's internals.
        let finished = try finishedView(game.view(for: .playerOne), signal: signal)
        let shouldRemind23 = tracker.consume(finished, matchID: matchID, isLive: true)
        #expect(!shouldRemind23)
        let shouldRemind24 = tracker.consume(finished, matchID: matchID, isLive: true)
        #expect(!shouldRemind24)
    }

    private func makeGame(startingPlayer: PlayerID) -> BattleLineGame {
        BattleLineGame(dealer: startingPlayer.opponent, seed: 42)
    }

    private func completeTurn(in game: inout BattleLineGame) throws {
        let actor = game.currentPlayer
        let card = try #require(game.hand(for: actor).first)
        let flag = try #require(game.legalFlags(for: actor).first)
        try game.apply(GameCommand(
            actor: actor, expectedVersion: game.version, action: .play(card: card, to: flag)
        ))
        try game.apply(GameCommand(
            actor: actor, expectedVersion: game.version, action: .declareClaims([])
        ))
    }

    enum CompletionSignal: CaseIterable, Sendable, Equatable {
        case winner
        case gameOver
        case both
    }

    private func finishedView(_ view: PlayerView, signal: CompletionSignal) throws -> PlayerView {
        var object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(view)) as? [String: Any]
        )
        if signal == .winner || signal == .both {
            object["winner"] = view.viewer.opponent.rawValue
        }
        if signal == .gameOver || signal == .both {
            object["phase"] = TurnPhase.gameOver.rawValue
        }
        return try JSONDecoder().decode(
            PlayerView.self, from: JSONSerialization.data(withJSONObject: object)
        )
    }
}

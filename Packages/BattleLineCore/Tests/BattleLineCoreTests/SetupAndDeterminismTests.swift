import Foundation
import Testing
@testable import BattleLineCore

@Suite("Setup and deterministic state")
struct SetupAndDeterminismTests {
    @Test("Creates the unique sixty-card deck, deals seven each, and starts left of dealer")
    func setup() {
        let game = BattleLineGame(dealer: .playerTwo, seed: 42)
        let allCards = game.hand(for: .playerOne) + game.hand(for: .playerTwo) + game.deck

        #expect(TroopCard.fullDeck.count == 60)
        #expect(Set(TroopCard.fullDeck).count == 60)
        #expect(allCards.count == 60)
        #expect(Set(allCards).count == 60)
        #expect(game.hand(for: .playerOne).count == 7)
        #expect(game.hand(for: .playerTwo).count == 7)
        #expect(game.deckCount == 46)
        #expect(game.currentPlayer == .playerOne)
        #expect(game.phase == .playing)
        #expect(game.flags.count == 9)
    }

    @Test("Equal seeds reproduce full host state; a different seed changes the deal")
    func seededReproducibility() {
        let first = BattleLineGame(dealer: .playerOne, seed: 0xBADD_CAFE)
        let second = BattleLineGame(dealer: .playerOne, seed: 0xBADD_CAFE)
        let different = BattleLineGame(dealer: .playerOne, seed: 0xBADD_CAFF)

        #expect(first == second)
        #expect(first.deck != different.deck || first.playerOneHand != different.playerOneHand)
    }

    @Test("Injected generators are consumed deterministically")
    func injectedGenerator() {
        var firstGenerator = SeededGenerator(seed: 99)
        var secondGenerator = SeededGenerator(seed: 99)
        let first = BattleLineGame(dealer: .playerTwo, using: &firstGenerator)
        let second = BattleLineGame(dealer: .playerTwo, using: &secondGenerator)

        #expect(first == second)
        #expect(firstGenerator == secondGenerator)
    }

    @Test("Authoritative state round-trips through Codable")
    func codableRoundTrip() throws {
        let game = BattleLineGame(
            configuration: .init(claimingRule: .advancedClaiming),
            dealer: .playerOne,
            seed: 1234
        )
        let data = try JSONEncoder().encode(game)
        let decoded = try JSONDecoder().decode(BattleLineGame.self, from: data)

        #expect(decoded == game)
        requireCodableAndSendable(BattleLineGame.self)
        requireCodableAndSendable(PlayerView.self)
        requireCodableAndSendable(GameCommand.self)
        requireCodableAndSendable(GameLogEntry.self)
    }
}

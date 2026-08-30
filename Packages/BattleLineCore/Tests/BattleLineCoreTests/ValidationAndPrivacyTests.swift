import Foundation
import Testing
@testable import BattleLineCore

@Suite("Host validation and hidden information")
struct ValidationAndPrivacyTests {
    @Test("Rejects stale versions and out-of-turn peers without mutation")
    func authorityChecks() {
        var game = BattleLineGame(dealer: .playerTwo, seed: 51)
        let original = game

        requireRuleError(.staleVersion(expected: 9, actual: 0)) {
            try game.apply(.init(actor: .playerOne, expectedVersion: 9, action: .pass))
        }
        requireRuleError(.notPlayersTurn(expected: .playerOne, actual: .playerTwo)) {
            try game.apply(.init(actor: .playerTwo, expectedVersion: 0, action: .pass))
        }
        #expect(game == original)
    }

    @Test("Rejects a card absent from the actor's hand")
    func absentCard() {
        var game = BattleLineGame(dealer: .playerTwo, seed: 52)
        let absent = TroopCard.fullDeck.first { !game.hand(for: .playerOne).contains($0) }!
        requireRuleError(.cardNotInHand(absent)) {
            try game.apply(
                .init(actor: .playerOne, expectedVersion: 0, action: .play(card: absent, to: FlagID(rawValue: 0)))
            )
        }
        #expect(game.version == 0)
        #expect(game.log.isEmpty)
    }

    @Test("Rejects placement on a claimed flag and a full formation")
    func illegalPlacementTargets() {
        let playable = card(.purple, 10)
        var claimedFlags = blankFlags()
        claimedFlags[0].claimedBy = .playerTwo
        var claimedGame = standardScenario(
            phase: .playing,
            flags: claimedFlags,
            playerOneHand: [playable]
        )
        requireRuleError(.cannotPlayOnClaimedFlag(flag: FlagID(rawValue: 0), by: .playerTwo)) {
            try claimedGame.apply(
                .init(actor: .playerOne, expectedVersion: 0, action: .play(card: playable, to: FlagID(rawValue: 0)))
            )
        }

        var fullFlags = blankFlags()
        fullFlags[0].playerOne = side([
            card(.red, 1), card(.blue, 1), card(.green, 1),
        ], completed: 1)
        var fullGame = standardScenario(
            phase: .playing,
            flags: fullFlags,
            playerOneHand: [playable]
        )
        requireRuleError(.formationFull(flag: FlagID(rawValue: 0), player: .playerOne)) {
            try fullGame.apply(
                .init(actor: .playerOne, expectedVersion: 0, action: .play(card: playable, to: FlagID(rawValue: 0)))
            )
        }
    }

    @Test("PlayerView reveals own cards but only opponent and deck counts")
    func sanitizedView() throws {
        let game = BattleLineGame(dealer: .playerOne, seed: 501)
        let view = game.view(for: .playerTwo)

        #expect(view.hand == game.hand(for: .playerTwo))
        #expect(view.opponent.player == .playerOne)
        #expect(view.opponent.handCount == 7)
        #expect(view.deckCount == 46)

        let encoded = try JSONEncoder().encode(view)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object["deck"] == nil)
        #expect(object["playerOneHand"] == nil)
        #expect(object["playerTwoHand"] == nil)
        let opponent = try #require(object["opponent"] as? [String: Any])
        #expect(opponent["handCount"] as? Int == 7)
        #expect(opponent["cards"] == nil)
    }

    @Test("Accepted actions advance version and append a public-safe log entry")
    func versionedLog() throws {
        var game = BattleLineGame(dealer: .playerTwo, seed: 77)
        let played = game.hand(for: .playerOne)[0]
        let receipt = try game.apply(
            .init(actor: .playerOne, expectedVersion: 0, action: .play(card: played, to: FlagID(rawValue: 5)))
        )

        #expect(receipt.version == 1)
        #expect(game.version == 1)
        #expect(game.log.count == 1)
        #expect(game.log[0].version == 1)
        #expect(game.log[0].actor == .playerOne)
        #expect(game.log[0].action == .play(card: played, to: FlagID(rawValue: 5)))
    }

    @Test("Wire decoding rejects forged card values and flag indices")
    func rejectsMalformedWireIdentifiers() {
        let invalidCard = Data(#"{"color":"red","value":11}"#.utf8)
        let invalidFlag = Data("9".utf8)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(TroopCard.self, from: invalidCard)
        }
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(FlagID.self, from: invalidFlag)
        }
    }
}

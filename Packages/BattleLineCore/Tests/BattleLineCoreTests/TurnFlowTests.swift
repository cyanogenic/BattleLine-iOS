import Testing
@testable import BattleLineCore

@Suite("Turn flow")
struct TurnFlowTests {
    @Test("Standard mode claims after placement and draws only after the claim window")
    func standardTurn() throws {
        var game = BattleLineGame(
            configuration: .init(claimingRule: .standard),
            dealer: .playerTwo,
            seed: 7
        )
        let cardToPlay = game.hand(for: .playerOne)[0]

        let playReceipt = try game.apply(
            .init(actor: .playerOne, expectedVersion: 0, action: .play(card: cardToPlay, to: FlagID(rawValue: 4)))
        )
        #expect(playReceipt.phase == .claimingAfterPlay)
        #expect(game.currentPlayer == .playerOne)
        #expect(game.hand(for: .playerOne).count == 6)
        #expect(game.deckCount == 46)

        let claimReceipt = try game.apply(
            .init(actor: .playerOne, expectedVersion: 1, action: .declareClaims([]))
        )
        #expect(claimReceipt.phase == .playing)
        #expect(game.currentPlayer == .playerTwo)
        #expect(game.hand(for: .playerOne).count == 7)
        #expect(game.deckCount == 45)
        #expect(game.turn == 2)
        #expect(game.version == 2)
        #expect(game.log.count == 2)
        #expect(claimReceipt.events.contains(.cardDrawn(player: .playerOne)))
    }

    @Test("Advanced mode exposes only a start-of-turn claim window")
    func advancedTurn() throws {
        var game = BattleLineGame(
            configuration: .init(claimingRule: .advancedClaiming),
            dealer: .playerTwo,
            seed: 8
        )
        let cardToPlay = game.hand(for: .playerOne)[0]

        requireRuleError(
            .actionNotAllowed(action: .play(card: cardToPlay, to: FlagID(rawValue: 0)), phase: .claimingAtTurnStart)
        ) {
            try game.apply(.init(actor: .playerOne, expectedVersion: 0, action: .play(card: cardToPlay, to: FlagID(rawValue: 0))))
        }

        try game.apply(.init(actor: .playerOne, expectedVersion: 0, action: .declareClaims([])))
        #expect(game.phase == .playing)
        #expect(game.version == 1)

        let receipt = try game.apply(
            .init(actor: .playerOne, expectedVersion: 1, action: .play(card: cardToPlay, to: FlagID(rawValue: 0)))
        )
        #expect(receipt.phase == .claimingAtTurnStart)
        #expect(game.currentPlayer == .playerTwo)
        #expect(game.hand(for: .playerOne).count == 7)
        #expect(game.deckCount == 45)
    }

    @Test("Deck exhaustion does not prevent play or turn advance")
    func emptyDeck() throws {
        var flags = blankFlags()
        let playable = card(.yellow, 5)
        var game = BattleLineGame(
            testingConfiguration: .init(claimingRule: .advancedClaiming),
            currentPlayer: .playerOne,
            phase: .playing,
            flags: flags,
            deck: [],
            playerOneHand: [playable]
        )

        let receipt = try game.apply(
            .init(actor: .playerOne, expectedVersion: 0, action: .play(card: playable, to: FlagID(rawValue: 3)))
        )
        flags = game.flags
        #expect(flags[3].playerOne.cards == [playable])
        #expect(game.hand(for: .playerOne).isEmpty)
        #expect(game.deckCount == 0)
        #expect(!receipt.events.contains(.cardDrawn(player: .playerOne)))
        #expect(game.currentPlayer == .playerTwo)
    }

    @Test("Playing a third troop records a monotonic completion order")
    func completionOrder() throws {
        var flags = blankFlags()
        flags[2].playerOne = side([card(.green, 3), card(.green, 4)])
        let completingCard = card(.green, 5)
        var game = standardScenario(
            phase: .playing,
            flags: flags,
            playerOneHand: [completingCard],
            lastCompletionOrder: 9
        )

        try game.apply(
            .init(
                actor: .playerOne,
                expectedVersion: 0,
                action: .play(card: completingCard, to: FlagID(rawValue: 2))
            )
        )
        #expect(game.flags[2].playerOne.completionOrder == 10)
        #expect(game.flags[2].playerOne.strength?.kind == .wedge)
    }

    @Test("Pass is legal only when no troop can be placed")
    func passing() throws {
        var normal = BattleLineGame(dealer: .playerTwo, seed: 1)
        requireRuleError(.passWhileLegalMoveExists) {
            try normal.apply(.init(actor: .playerOne, expectedVersion: 0, action: .pass))
        }

        var flags = blankFlags()
        for index in flags.indices {
            flags[index].playerOne = side([
                card(.red, (index % 10) + 1),
                card(.blue, (index % 10) + 1),
                card(.green, (index % 10) + 1),
            ], completed: UInt64(index + 1))
        }
        var blocked = standardScenario(
            phase: .playing,
            flags: flags,
            deck: [card(.yellow, 10)],
            playerOneHand: [card(.purple, 10)]
        )
        try blocked.apply(.init(actor: .playerOne, expectedVersion: 0, action: .pass))
        #expect(blocked.phase == .claimingAfterPlay)
        try blocked.apply(.init(actor: .playerOne, expectedVersion: 1, action: .declareClaims([])))
        #expect(blocked.currentPlayer == .playerTwo)
        #expect(blocked.deckCount == 1)
        #expect(blocked.hand(for: .playerOne) == [card(.purple, 10)])
    }
}

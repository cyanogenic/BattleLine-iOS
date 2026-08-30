import Testing
@testable import BattleLineCore

@Suite("Victory conditions")
struct VictoryTests {
    @Test("Claiming a third consecutive flag wins immediately")
    func threeConsecutive() throws {
        var flags = blankFlags()
        flags[2].claimedBy = .playerOne
        flags[3].claimedBy = .playerOne
        flags[4].playerOne = side([card(.red, 8), card(.red, 9), card(.red, 10)], completed: 1)
        var game = standardScenario(
            flags: flags,
            deck: [card(.green, 1)]
        )

        let receipt = try game.apply(
            .init(actor: .playerOne, expectedVersion: 0, action: .declareClaims([FlagID(rawValue: 4)]))
        )
        #expect(game.winner == .playerOne)
        #expect(game.phase == .gameOver)
        #expect(game.currentPlayer == .playerOne)
        #expect(game.deckCount == 1)
        #expect(receipt.events.contains(.gameWon(player: .playerOne)))
    }

    @Test("Claiming any fifth flag wins without requiring adjacency")
    func anyFive() throws {
        var flags = blankFlags()
        for index in [0, 2, 4, 6] {
            flags[index].claimedBy = .playerTwo
        }
        flags[8].playerTwo = side([card(.blue, 8), card(.blue, 9), card(.blue, 10)], completed: 1)
        var game = standardScenario(currentPlayer: .playerTwo, flags: flags)

        try game.apply(
            .init(actor: .playerTwo, expectedVersion: 0, action: .declareClaims([FlagID(rawValue: 8)]))
        )
        #expect(game.winner == .playerTwo)
        #expect(game.flags.filter { $0.claimedBy == .playerTwo }.count == 5)
    }

    @Test("No command is accepted after victory")
    func actionsAfterVictory() {
        var flags = blankFlags()
        flags[0].claimedBy = .playerOne
        flags[1].claimedBy = .playerOne
        var game = BattleLineGame(
            testingConfiguration: .init(),
            currentPlayer: .playerOne,
            phase: .gameOver,
            flags: flags,
            winner: .playerOne
        )

        requireRuleError(.gameAlreadyOver(winner: .playerOne)) {
            try game.apply(.init(actor: .playerOne, expectedVersion: 0, action: .pass))
        }
    }

    @Test("A multi-claim stops at the first flag that completes victory")
    func multiClaimStopsImmediately() throws {
        var flags = blankFlags()
        flags[0].claimedBy = .playerOne
        flags[1].claimedBy = .playerOne
        flags[2].playerOne = side([
            card(.red, 8), card(.red, 9), card(.red, 10),
        ], completed: 1)
        // This later declaration is intentionally invalid. It must never be
        // validated because flag 2 has already ended the match.
        flags[8].playerOne = side([card(.blue, 1)])
        var game = standardScenario(flags: flags)

        let receipt = try game.apply(
            .init(
                actor: .playerOne,
                expectedVersion: 0,
                action: .declareClaims([FlagID(rawValue: 2), FlagID(rawValue: 8)])
            )
        )

        #expect(game.winner == .playerOne)
        #expect(game.flags[2].claimedBy == .playerOne)
        #expect(game.flags[8].claimedBy == nil)
        #expect(receipt.events.contains(
            .claimsDeclared(player: .playerOne, flags: [FlagID(rawValue: 2)])
        ))
    }
}

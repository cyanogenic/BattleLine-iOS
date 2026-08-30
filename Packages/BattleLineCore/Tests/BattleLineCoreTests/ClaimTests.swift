import Testing
@testable import BattleLineCore

@Suite("Claim proof")
struct ClaimTests {
    @Test("Complete formations compare by kind and then total")
    func completeFormationComparison() {
        var flags = blankFlags()
        flags[0] = FlagState(
            id: FlagID(rawValue: 0),
            playerOne: side([card(.red, 1), card(.red, 2), card(.red, 3)], completed: 2),
            playerTwo: side([card(.red, 10), card(.blue, 10), card(.green, 10)], completed: 1)
        )
        flags[1] = FlagState(
            id: FlagID(rawValue: 1),
            playerOne: side([card(.orange, 2), card(.orange, 7), card(.orange, 10)], completed: 3),
            playerTwo: side([card(.blue, 1), card(.blue, 5), card(.blue, 10)], completed: 4)
        )
        let game = standardScenario(flags: flags)

        #expect(game.evaluateClaim(on: FlagID(rawValue: 0), by: .playerOne).isClaimable)
        #expect(game.evaluateClaim(on: FlagID(rawValue: 1), by: .playerOne).isClaimable)
        #expect(!game.evaluateClaim(on: FlagID(rawValue: 1), by: .playerTwo).isClaimable)
    }

    @Test("Equal complete formations go to the side completed first")
    func completionOrderTieBreak() {
        var flags = blankFlags()
        flags[0] = FlagState(
            id: FlagID(rawValue: 0),
            playerOne: side([card(.red, 4), card(.blue, 5), card(.green, 6)], completed: 11),
            playerTwo: side([card(.orange, 4), card(.yellow, 5), card(.purple, 6)], completed: 12)
        )
        let game = standardScenario(flags: flags)

        #expect(game.evaluateClaim(on: FlagID(rawValue: 0), by: .playerOne).isClaimable)
        #expect(!game.evaluateClaim(on: FlagID(rawValue: 0), by: .playerTwo).isClaimable)
    }

    @Test("Incomplete opponent is credited with its strongest public-table possibility")
    func incompleteOpponentEnumeration() {
        var flags = blankFlags()
        flags[0] = FlagState(
            id: FlagID(rawValue: 0),
            playerOne: side([card(.red, 7), card(.red, 8), card(.red, 9)], completed: 1),
            playerTwo: side([])
        )
        let game = standardScenario(flags: flags)
        let evaluation = game.evaluateClaim(on: FlagID(rawValue: 0), by: .playerOne)

        #expect(!evaluation.isClaimable)
        #expect(evaluation.claimantStrength == FormationStrength(cards: [card(.red, 7), card(.red, 8), card(.red, 9)]))
        #expect(evaluation.strongestPossibleOpponentFormation == FormationStrength(cards: [
            card(.blue, 8), card(.blue, 9), card(.blue, 10),
        ]))
    }

    @Test("The maximum wedge is provable against an incomplete opponent")
    func provableMaximum() {
        var flags = blankFlags()
        flags[0] = FlagState(
            id: FlagID(rawValue: 0),
            playerOne: side([card(.red, 8), card(.red, 9), card(.red, 10)], completed: 1),
            playerTwo: side([card(.purple, 8), card(.purple, 9)])
        )
        let game = standardScenario(flags: flags)
        let evaluation = game.evaluateClaim(on: FlagID(rawValue: 0), by: .playerOne)

        #expect(evaluation.isClaimable)
        #expect(evaluation.strongestPossibleOpponentFormation?.kind == .wedge)
        #expect(evaluation.strongestPossibleOpponentFormation?.total == 27)
    }

    @Test("Proof ignores both hidden hands and deck order")
    func publicInformationOnly() {
        var flags = blankFlags()
        flags[0] = FlagState(
            id: FlagID(rawValue: 0),
            playerOne: side([card(.red, 8), card(.red, 9), card(.red, 10)], completed: 1),
            playerTwo: side([card(.blue, 8), card(.blue, 9)])
        )
        let first = standardScenario(
            flags: flags,
            deck: [card(.green, 1), card(.blue, 10)],
            playerOneHand: [card(.purple, 10)],
            playerTwoHand: [card(.yellow, 2)]
        )
        let second = standardScenario(
            flags: flags,
            deck: [card(.orange, 7)],
            playerOneHand: [card(.blue, 10), card(.green, 6)],
            playerTwoHand: [card(.purple, 1), card(.yellow, 10)]
        )

        #expect(first.evaluateClaim(on: FlagID(rawValue: 0), by: .playerOne)
            == second.evaluateClaim(on: FlagID(rawValue: 0), by: .playerOne))
    }

    @Test("A multi-claim command is atomic")
    func atomicClaims() {
        var flags = blankFlags()
        flags[0].playerOne = side([card(.red, 8), card(.red, 9), card(.red, 10)], completed: 1)
        flags[1].playerOne = side([card(.blue, 8), card(.blue, 9)])
        var game = standardScenario(flags: flags)

        requireRuleError(.flagNotClaimable(FlagID(rawValue: 1))) {
            try game.apply(
                .init(
                    actor: .playerOne,
                    expectedVersion: 0,
                    action: .declareClaims([FlagID(rawValue: 0), FlagID(rawValue: 1)])
                )
            )
        }
        #expect(game.flags[0].claimedBy == nil)
        #expect(game.flags[1].claimedBy == nil)
        #expect(game.version == 0)
        #expect(game.log.isEmpty)
    }

    @Test("Duplicate declarations and incomplete claimant formations are rejected")
    func malformedClaims() {
        let flag = FlagID(rawValue: 0)
        var duplicateFlags = blankFlags()
        duplicateFlags[0].playerOne = side([
            card(.red, 8), card(.red, 9), card(.red, 10),
        ], completed: 1)
        var duplicateGame = standardScenario(flags: duplicateFlags)
        requireRuleError(.duplicateClaim(flag)) {
            try duplicateGame.apply(
                .init(actor: .playerOne, expectedVersion: 0, action: .declareClaims([flag, flag]))
            )
        }

        var incompleteGame = standardScenario(flags: blankFlags())
        requireRuleError(.flagNotClaimable(flag)) {
            try incompleteGame.apply(
                .init(actor: .playerOne, expectedVersion: 0, action: .declareClaims([flag]))
            )
        }
    }
}

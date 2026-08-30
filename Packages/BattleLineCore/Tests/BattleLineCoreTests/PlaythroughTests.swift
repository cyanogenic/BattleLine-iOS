import Testing
@testable import BattleLineCore

@Suite("Deterministic end-to-end playthrough")
struct PlaythroughTests {
    @Test(
        "Both claiming modes preserve the deck and reach a rules victory",
        arguments: [ClaimingRule.standard, .advancedClaiming]
    )
    func completeMatch(claimingRule: ClaimingRule) throws {
        var game = BattleLineGame(
            configuration: .init(claimingRule: claimingRule),
            dealer: .playerOne,
            seed: 0xCAFE_F00D
        )

        for _ in 0 ..< 500 where game.winner == nil {
            let actor = game.currentPlayer
            switch game.phase {
            case .claimingAtTurnStart, .claimingAfterPlay:
                let claims = game.flags.compactMap { flag -> FlagID? in
                    guard flag.claimedBy == nil,
                          flag.formation(for: actor).isComplete,
                          game.evaluateClaim(on: flag.id, by: actor).isClaimable
                    else { return nil }
                    return flag.id
                }
                try game.apply(
                    .init(actor: actor, expectedVersion: game.version, action: .declareClaims(claims))
                )

            case .playing:
                if let card = game.hand(for: actor).first,
                   let flag = game.legalFlags(for: actor).first
                {
                    try game.apply(
                        .init(actor: actor, expectedVersion: game.version, action: .play(card: card, to: flag))
                    )
                } else {
                    try game.apply(
                        .init(actor: actor, expectedVersion: game.version, action: .pass)
                    )
                }

            case .gameOver:
                break
            }

            let allCards = game.deck
                + game.hand(for: .playerOne)
                + game.hand(for: .playerTwo)
                + game.flags.flatMap { $0.playerOne.cards + $0.playerTwo.cards }
            #expect(allCards.count == 60)
            #expect(Set(allCards).count == 60)
            #expect(game.log.count == Int(game.version))
        }

        #expect(game.winner != nil)
        #expect(game.phase == .gameOver)
        let winner = try #require(game.winner)
        let claimed = game.flags.filter { $0.claimedBy == winner }.map(\.id.rawValue)
        let claimedSet = Set(claimed)
        let hasThreeAdjacent = (0 ... 6).contains { start in
            claimedSet.contains(start)
                && claimedSet.contains(start + 1)
                && claimedSet.contains(start + 2)
        }
        #expect(claimed.count >= 5 || hasThreeAdjacent)
    }
}

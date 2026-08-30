import Testing
@testable import BattleLineCore

func card(_ color: TroopColor, _ value: Int) -> TroopCard {
    try! TroopCard(color: color, value: value)
}

func blankFlags() -> [FlagState] {
    FlagID.all.map { FlagState(id: $0) }
}

func side(_ cards: [TroopCard], completed order: UInt64? = nil) -> FormationSide {
    FormationSide(cards: cards, completionOrder: order)
}

func standardScenario(
    currentPlayer: PlayerID = .playerOne,
    phase: TurnPhase = .claimingAfterPlay,
    flags: [FlagState],
    deck: [TroopCard] = [],
    playerOneHand: [TroopCard] = [],
    playerTwoHand: [TroopCard] = [],
    lastCompletionOrder: UInt64 = 0
) -> BattleLineGame {
    BattleLineGame(
        testingConfiguration: .init(claimingRule: .standard),
        currentPlayer: currentPlayer,
        phase: phase,
        flags: flags,
        deck: deck,
        playerOneHand: playerOneHand,
        playerTwoHand: playerTwoHand,
        lastCompletionOrder: lastCompletionOrder
    )
}

func requireRuleError(
    _ expected: GameRuleError,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ operation: () throws -> Void
) {
    do {
        try operation()
        Issue.record("Expected \(expected), but no error was thrown", sourceLocation: sourceLocation)
    } catch let actual as GameRuleError {
        #expect(actual == expected, sourceLocation: sourceLocation)
    } catch {
        Issue.record("Expected GameRuleError but received \(error)", sourceLocation: sourceLocation)
    }
}

func requireCodableAndSendable<T: Codable & Sendable>(_: T.Type) {}

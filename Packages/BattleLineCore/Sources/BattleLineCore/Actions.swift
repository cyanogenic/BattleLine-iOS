import Foundation

public enum GameAction: Codable, Sendable, Equatable {
    /// Declares claims in the requested order for the current claim window.
    /// An empty array explicitly skips claiming and advances the turn phase. If
    /// a declaration wins the game, later entries are intentionally ignored.
    case declareClaims([FlagID])
    case play(card: TroopCard, to: FlagID)
    case pass
}

/// A client command is accepted only when its actor, phase, and expected version
/// match the authoritative host state.
public struct GameCommand: Codable, Sendable, Equatable {
    public let actor: PlayerID
    public let expectedVersion: UInt64
    public let action: GameAction

    public init(actor: PlayerID, expectedVersion: UInt64, action: GameAction) {
        self.actor = actor
        self.expectedVersion = expectedVersion
        self.action = action
    }
}

public enum GameEvent: Codable, Sendable, Equatable {
    case claimsDeclared(player: PlayerID, flags: [FlagID])
    case cardPlayed(player: PlayerID, card: TroopCard, flag: FlagID)
    /// The identity is deliberately omitted so logs are safe to expose to both peers.
    case cardDrawn(player: PlayerID)
    case passed(player: PlayerID)
    case turnChanged(player: PlayerID, turn: UInt64)
    case gameWon(player: PlayerID)
}

public struct GameLogEntry: Codable, Sendable, Equatable {
    public let version: UInt64
    public let turn: UInt64
    public let actor: PlayerID
    public let action: GameAction
    public let events: [GameEvent]

    public init(
        version: UInt64,
        turn: UInt64,
        actor: PlayerID,
        action: GameAction,
        events: [GameEvent]
    ) {
        self.version = version
        self.turn = turn
        self.actor = actor
        self.action = action
        self.events = events
    }
}

public struct ActionReceipt: Codable, Sendable, Equatable {
    public let version: UInt64
    public let phase: TurnPhase
    public let events: [GameEvent]
    public let winner: PlayerID?
}

public enum GameRuleError: Error, Codable, Sendable, Equatable {
    case staleVersion(expected: UInt64, actual: UInt64)
    case gameAlreadyOver(winner: PlayerID)
    case notPlayersTurn(expected: PlayerID, actual: PlayerID)
    case actionNotAllowed(action: GameAction, phase: TurnPhase)
    case duplicateClaim(FlagID)
    case flagAlreadyClaimed(flag: FlagID, by: PlayerID)
    case flagNotClaimable(FlagID)
    case cardNotInHand(TroopCard)
    case formationFull(flag: FlagID, player: PlayerID)
    case cannotPlayOnClaimedFlag(flag: FlagID, by: PlayerID)
    case passWhileLegalMoveExists
}

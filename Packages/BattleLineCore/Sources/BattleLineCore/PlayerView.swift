import Foundation

public struct OpponentView: Codable, Sendable, Equatable {
    public let player: PlayerID
    public let handCount: Int
}

/// The only state representation that should cross from the authoritative host
/// to a player. It never contains the opponent's cards or the deck's order.
public struct PlayerView: Codable, Sendable, Equatable {
    public let viewer: PlayerID
    public let configuration: GameConfiguration
    public let dealer: PlayerID
    public let currentPlayer: PlayerID
    public let phase: TurnPhase
    public let turn: UInt64
    public let version: UInt64
    public let hand: [TroopCard]
    public let opponent: OpponentView
    public let deckCount: Int
    public let flags: [FlagState]
    public let winner: PlayerID?
    public let log: [GameLogEntry]
}

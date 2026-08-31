import BattleLineCore
import Foundation

/// Consumes authoritative views even when feedback is muted or the app is inactive.
/// This prevents a previously suppressed turn from being replayed later.
struct TurnReminderTracker {
    private struct State {
        let matchID: UUID
        let viewer: PlayerID
        let currentPlayer: PlayerID
        let turn: UInt64
        let version: UInt64
        let isFinished: Bool
    }

    private var previous: State?

    mutating func consume(_ view: PlayerView, matchID: UUID, isLive: Bool) -> Bool {
        let next = State(
            matchID: matchID, viewer: view.viewer, currentPlayer: view.currentPlayer,
            turn: view.turn, version: view.version,
            isFinished: view.winner != nil || view.phase == .gameOver
        )
        guard let old = previous, old.matchID == matchID, old.viewer == view.viewer else {
            previous = next
            return false
        }
        // Equal-version snapshots are intentionally allowed by the transport, but
        // must not replay feedback. Never let an older view rewind the baseline.
        guard next.version > old.version, next.turn >= old.turn else { return false }
        previous = next
        return isLive && !old.isFinished && !next.isFinished
            && old.currentPlayer == view.viewer.opponent
            && next.currentPlayer == view.viewer
            && next.turn > old.turn
    }

    mutating func reset() {
        previous = nil
    }
}

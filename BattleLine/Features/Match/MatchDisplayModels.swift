import BattleLineCore
import Foundation
import Observation

enum FlagOwnerPresentation: String, Codable, Sendable {
    case player
    case opponent
}

struct BattleLinePresentation: Identifiable, Hashable, Codable, Sendable {
    let id: Int
    var opponentCards: [TroopCardPresentation]
    var playerCards: [TroopCardPresentation]
    var owner: FlagOwnerPresentation?
    var isClaimable: Bool
}

enum MatchPhasePresentation: Equatable, Sendable {
    case waitingForOpponent
    case claiming
    case playCard
    case waitingForOpponentTurn
    case paused(String)
    case finished(winner: FlagOwnerPresentation)
}

@MainActor
@Observable
final class MatchViewModel {
    var localPlayerName = "玩家"
    var opponentName = "等待加入"
    var connectionText = "正在启动蓝牙"
    var pairingCode = "••• •••"
    var lines: [BattleLinePresentation] = MatchViewModel.emptyLines
    var hand: [TroopCardPresentation] = []
    var phase: MatchPhasePresentation = .waitingForOpponent
    var selectedCardID: String?
    var selectedLineID: Int?
    /// Selection order is preserved because a winning claim ends the match
    /// immediately; later claims in the same declaration must not be applied.
    var selectedClaimIDs: [Int] = []
    var deckCount = 46
    var opponentHandCount = 7
    var turn: UInt64 = 1
    var stateVersion: UInt64 = 0
    var notice: String?
    var isSubmitting = false

    @ObservationIgnored
    private var actionHandler: ((GameAction) -> Void)?

    var selectedCard: TroopCardPresentation? {
        hand.first { $0.id == selectedCardID }
    }

    var claimableLines: [BattleLinePresentation] {
        lines.filter(\.isClaimable)
    }

    var hasLegalPlay: Bool {
        !hand.isEmpty && lines.contains {
            $0.owner == nil && $0.playerCards.count < 3
        }
    }

    func setActionHandler(_ handler: @escaping (GameAction) -> Void) {
        actionHandler = handler
    }

    func prepareForHost(name: String, code: String) {
        resetBoard()
        localPlayerName = name
        opponentName = "等待加入"
        pairingCode = code
        connectionText = "正在广播纯蓝牙房间"
        phase = .waitingForOpponent
    }

    func prepareForGuest(name: String) {
        resetBoard()
        localPlayerName = name
        opponentName = "正在寻找房主"
        connectionText = "正在扫描附近房间"
        phase = .waitingForOpponent
    }

    func update(
        from view: PlayerView,
        claimableFlagIndices: [Int],
        localName: String,
        opponentName: String
    ) {
        let viewer = view.viewer
        let claimable = Set(claimableFlagIndices)

        self.localPlayerName = localName
        self.opponentName = opponentName
        hand = view.hand.map(TroopCardPresentation.init)
        deckCount = view.deckCount
        opponentHandCount = view.opponent.handCount
        turn = view.turn
        stateVersion = view.version
        lines = view.flags.map { flag in
            let owner: FlagOwnerPresentation?
            switch flag.claimedBy {
            case viewer:
                owner = .player
            case viewer.opponent:
                owner = .opponent
            case nil:
                owner = nil
            default:
                owner = nil
            }

            return BattleLinePresentation(
                id: flag.id.rawValue,
                opponentCards: flag.formation(for: viewer.opponent).cards.map(TroopCardPresentation.init),
                playerCards: flag.formation(for: viewer).cards.map(TroopCardPresentation.init),
                owner: owner,
                isClaimable: claimable.contains(flag.id.rawValue)
            )
        }

        selectedCardID = nil
        selectedLineID = nil
        selectedClaimIDs = selectedClaimIDs.filter(claimable.contains)
        isSubmitting = false
        notice = nil

        if let winner = view.winner {
            phase = .finished(winner: winner == viewer ? .player : .opponent)
        } else if view.currentPlayer != viewer {
            phase = .waitingForOpponentTurn
        } else {
            switch view.phase {
            case .claimingAtTurnStart, .claimingAfterPlay:
                phase = .claiming
            case .playing:
                phase = .playCard
            case .gameOver:
                phase = .finished(winner: .opponent)
            }
        }
    }

    func markConnected() {
        connectionText = "纯蓝牙已连接"
    }

    func markPaused(_ reason: String) {
        connectionText = "连接中断"
        phase = .paused(reason)
        isSubmitting = false
    }

    func showError(_ message: String) {
        notice = message
        isSubmitting = false
    }

    func disconnect() {
        selectedCardID = nil
        selectedLineID = nil
        selectedClaimIDs = []
        phase = .waitingForOpponent
        connectionText = "已断开"
        isSubmitting = false
    }

    func selectCard(_ card: TroopCardPresentation) {
        guard phase == .playCard, !isSubmitting else { return }
        selectedCardID = selectedCardID == card.id ? nil : card.id
    }

    func selectLine(_ line: BattleLinePresentation) {
        guard phase == .playCard,
              !isSubmitting,
              line.owner == nil,
              line.playerCards.count < 3
        else { return }
        selectedLineID = selectedLineID == line.id ? nil : line.id
    }

    func toggleClaim(_ line: BattleLinePresentation) {
        guard phase == .claiming, line.isClaimable, !isSubmitting else { return }
        if selectedClaimIDs.contains(line.id) {
            selectedClaimIDs.removeAll { $0 == line.id }
        } else {
            selectedClaimIDs.append(line.id)
        }
    }

    func confirmPlay() {
        guard phase == .playCard,
              !isSubmitting,
              let selectedCard,
              let selectedLineID,
              let coreCard = selectedCard.coreCard,
              let flag = try? FlagID(validating: selectedLineID)
        else { return }

        submit(.play(card: coreCard, to: flag))
    }

    func confirmClaims() {
        guard phase == .claiming, !isSubmitting else { return }
        let flags = selectedClaimIDs.compactMap { try? FlagID(validating: $0) }
        submit(.declareClaims(flags))
    }

    func pass() {
        guard phase == .playCard, !hasLegalPlay, !isSubmitting else { return }
        submit(.pass)
    }

    private func submit(_ action: GameAction) {
        notice = nil
        isSubmitting = true
        actionHandler?(action)
    }

    private func resetBoard() {
        lines = Self.emptyLines
        hand = []
        selectedCardID = nil
        selectedLineID = nil
        selectedClaimIDs = []
        deckCount = 46
        opponentHandCount = 7
        turn = 1
        stateVersion = 0
        notice = nil
        isSubmitting = false
    }

    private static var emptyLines: [BattleLinePresentation] {
        (0 ..< 9).map { index in
            BattleLinePresentation(
                id: index,
                opponentCards: [],
                playerCards: [],
                owner: nil,
                isClaimable: false
            )
        }
    }

    static func preview() -> MatchViewModel {
        let model = MatchViewModel()
        model.lines = (0 ..< 9).map { index in
            BattleLinePresentation(
                id: index,
                opponentCards: index.isMultiple(of: 2)
                    ? [TroopCardPresentation(color: .orange, value: min(index + 2, 10))]
                    : [],
                playerCards: index.isMultiple(of: 3)
                    ? [TroopCardPresentation(color: .blue, value: min(index + 3, 10))]
                    : [],
                owner: nil,
                isClaimable: false
            )
        }
        model.hand = [
            TroopCardPresentation(color: .red, value: 2),
            TroopCardPresentation(color: .orange, value: 9),
            TroopCardPresentation(color: .yellow, value: 6),
            TroopCardPresentation(color: .green, value: 8),
            TroopCardPresentation(color: .blue, value: 5),
            TroopCardPresentation(color: .purple, value: 3),
            TroopCardPresentation(color: .red, value: 10),
        ]
        model.phase = .playCard
        model.connectionText = "纯蓝牙已连接"
        model.opponentName = "对手"
        return model
    }
}

private extension TroopCardPresentation {
    init(_ card: TroopCard) {
        self.init(
            color: TroopColorPresentation(card.color),
            value: card.value
        )
    }

    var coreCard: TroopCard? {
        try? TroopCard(color: color.coreColor, value: value)
    }
}

private extension TroopColorPresentation {
    init(_ color: TroopColor) {
        switch color {
        case .red: self = .red
        case .orange: self = .orange
        case .yellow: self = .yellow
        case .green: self = .green
        case .blue: self = .blue
        case .purple: self = .purple
        }
    }

    var coreColor: TroopColor {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .blue: .blue
        case .purple: .purple
        }
    }
}

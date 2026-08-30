import Foundation

/// Authoritative, deterministic Battle Line rules state.
///
/// Keep this value on the host. Send `view(for:)` to a peer so hidden hands and
/// deck order never leave the authority boundary.
public struct BattleLineGame: Codable, Sendable, Equatable {
    public let configuration: GameConfiguration
    public let dealer: PlayerID

    public internal(set) var currentPlayer: PlayerID
    public internal(set) var phase: TurnPhase
    public internal(set) var turn: UInt64
    public internal(set) var version: UInt64
    public internal(set) var flags: [FlagState]
    public internal(set) var winner: PlayerID?
    public internal(set) var log: [GameLogEntry]

    // Host-only information. It is intentionally absent from PlayerView.
    internal var deck: [TroopCard]
    internal var playerOneHand: [TroopCard]
    internal var playerTwoHand: [TroopCard]
    internal var lastCompletionOrder: UInt64
    internal var shouldDrawAfterClaimWindow: Bool

    public init(
        configuration: GameConfiguration = .init(),
        dealer: PlayerID,
        seed: UInt64
    ) {
        var generator = SeededGenerator(seed: seed)
        self.init(configuration: configuration, dealer: dealer, using: &generator)
    }

    /// Inject any `RandomNumberGenerator`; the supplied generator is the only
    /// source of randomness used to construct the match.
    public init<R: RandomNumberGenerator>(
        configuration: GameConfiguration = .init(),
        dealer: PlayerID,
        using generator: inout R
    ) {
        self.configuration = configuration
        self.dealer = dealer
        currentPlayer = dealer.opponent
        phase = configuration.claimingRule == .advancedClaiming
            ? .claimingAtTurnStart
            : .playing
        turn = 1
        version = 0
        flags = FlagID.all.map { FlagState(id: $0) }
        winner = nil
        log = []
        deck = DeckShuffler.shuffled(TroopCard.fullDeck, using: &generator)
        playerOneHand = []
        playerTwoHand = []
        lastCompletionOrder = 0
        shouldDrawAfterClaimWindow = false

        // Deal clockwise beginning with the non-dealer.
        for _ in 0 ..< 7 {
            drawInitialCard(for: dealer.opponent)
            drawInitialCard(for: dealer)
        }
    }

    public var deckCount: Int { deck.count }

    public func hand(for player: PlayerID) -> [TroopCard] {
        switch player {
        case .playerOne: playerOneHand
        case .playerTwo: playerTwoHand
        }
    }

    public func formation(on flag: FlagID, for player: PlayerID) -> FormationSide {
        flags[flag.rawValue].formation(for: player)
    }

    public func legalFlags(for player: PlayerID) -> [FlagID] {
        flags.compactMap { flag in
            guard flag.claimedBy == nil,
                  flag.formation(for: player).cards.count < 3
            else { return nil }
            return flag.id
        }
    }

    public func hasLegalPlay(for player: PlayerID) -> Bool {
        !hand(for: player).isEmpty && !legalFlags(for: player).isEmpty
    }

    /// Evaluates a claim without consulting either hand or the deck order.
    /// For an incomplete opponent, every card not visible on the battlefield is
    /// conservatively treated as available to that opponent.
    public func evaluateClaim(on flagID: FlagID, by claimant: PlayerID) -> ClaimEvaluation {
        let flag = flags[flagID.rawValue]
        if let owner = flag.claimedBy {
            return ClaimEvaluation(
                flag: flagID,
                claimant: claimant,
                claimantStrength: flag.formation(for: claimant).strength,
                strongestPossibleOpponentFormation: flag.formation(for: claimant.opponent).strength,
                blockReason: .alreadyClaimed(by: owner)
            )
        }

        let claimantFormation = flag.formation(for: claimant)
        guard let claimantStrength = claimantFormation.strength else {
            return ClaimEvaluation(
                flag: flagID,
                claimant: claimant,
                claimantStrength: nil,
                strongestPossibleOpponentFormation: nil,
                blockReason: .claimantFormationIncomplete
            )
        }

        let opponentFormation = flag.formation(for: claimant.opponent)
        if let opponentStrength = opponentFormation.strength {
            let claimantWins: Bool
            if claimantStrength != opponentStrength {
                claimantWins = claimantStrength > opponentStrength
            } else {
                let claimantOrder = claimantFormation.completionOrder ?? UInt64.max
                let opponentOrder = opponentFormation.completionOrder ?? UInt64.max
                claimantWins = claimantOrder < opponentOrder
            }
            return ClaimEvaluation(
                flag: flagID,
                claimant: claimant,
                claimantStrength: claimantStrength,
                strongestPossibleOpponentFormation: opponentStrength,
                blockReason: claimantWins ? nil : .opponentFormationWins
            )
        }

        let opponentBest = strongestPubliclyPossibleFormation(
            extending: opponentFormation.cards
        )
        let blockReason: ClaimBlockReason?
        if let opponentBest, opponentBest > claimantStrength {
            blockReason = .opponentCanStillBuild(strength: opponentBest)
        } else {
            // An equal future formation loses because the claimant completed first.
            blockReason = nil
        }

        return ClaimEvaluation(
            flag: flagID,
            claimant: claimant,
            claimantStrength: claimantStrength,
            strongestPossibleOpponentFormation: opponentBest,
            blockReason: blockReason
        )
    }

    /// Validates and applies a peer command atomically against host state.
    @discardableResult
    public mutating func apply(_ command: GameCommand) throws -> ActionReceipt {
        guard command.expectedVersion == version else {
            throw GameRuleError.staleVersion(expected: command.expectedVersion, actual: version)
        }
        if let winner {
            throw GameRuleError.gameAlreadyOver(winner: winner)
        }
        guard command.actor == currentPlayer else {
            throw GameRuleError.notPlayersTurn(expected: currentPlayer, actual: command.actor)
        }

        let actionTurn = turn
        var events: [GameEvent]
        switch command.action {
        case let .declareClaims(flagIDs):
            events = try applyClaims(flagIDs, by: command.actor)
        case let .play(card, flagID):
            events = try applyPlay(card, to: flagID, by: command.actor)
        case .pass:
            events = try applyPass(by: command.actor)
        }

        version += 1
        log.append(
            GameLogEntry(
                version: version,
                turn: actionTurn,
                actor: command.actor,
                action: command.action,
                events: events
            )
        )
        return ActionReceipt(version: version, phase: phase, events: events, winner: winner)
    }

    public func view(for viewer: PlayerID) -> PlayerView {
        PlayerView(
            viewer: viewer,
            configuration: configuration,
            dealer: dealer,
            currentPlayer: currentPlayer,
            phase: phase,
            turn: turn,
            version: version,
            hand: hand(for: viewer),
            opponent: OpponentView(
                player: viewer.opponent,
                handCount: hand(for: viewer.opponent).count
            ),
            deckCount: deck.count,
            flags: flags,
            winner: winner,
            log: log
        )
    }

    private mutating func drawInitialCard(for player: PlayerID) {
        guard let card = deck.popLast() else { return }
        appendToHand(card, for: player)
    }

    private mutating func appendToHand(_ card: TroopCard, for player: PlayerID) {
        switch player {
        case .playerOne: playerOneHand.append(card)
        case .playerTwo: playerTwoHand.append(card)
        }
    }

    private mutating func removeFromHand(_ card: TroopCard, for player: PlayerID) -> Bool {
        switch player {
        case .playerOne:
            guard let index = playerOneHand.firstIndex(of: card) else { return false }
            playerOneHand.remove(at: index)
        case .playerTwo:
            guard let index = playerTwoHand.firstIndex(of: card) else { return false }
            playerTwoHand.remove(at: index)
        }
        return true
    }

    private mutating func drawTurnCard(for player: PlayerID, events: inout [GameEvent]) {
        guard let card = deck.popLast() else { return }
        appendToHand(card, for: player)
        events.append(.cardDrawn(player: player))
    }

    private mutating func applyPlay(
        _ card: TroopCard,
        to flagID: FlagID,
        by player: PlayerID
    ) throws -> [GameEvent] {
        guard phase == .playing else {
            throw GameRuleError.actionNotAllowed(action: .play(card: card, to: flagID), phase: phase)
        }
        guard hand(for: player).contains(card) else {
            throw GameRuleError.cardNotInHand(card)
        }

        let flag = flags[flagID.rawValue]
        if let owner = flag.claimedBy {
            throw GameRuleError.cannotPlayOnClaimedFlag(flag: flagID, by: owner)
        }
        guard flag.formation(for: player).cards.count < 3 else {
            throw GameRuleError.formationFull(flag: flagID, player: player)
        }

        // All validation is complete before the first mutation.
        _ = removeFromHand(card, for: player)
        flags[flagID.rawValue].updateFormation(for: player) { formation in
            formation.cards.append(card)
            if formation.cards.count == 3 {
                lastCompletionOrder += 1
                formation.completionOrder = lastCompletionOrder
            }
        }

        var events: [GameEvent] = [.cardPlayed(player: player, card: card, flag: flagID)]
        switch configuration.claimingRule {
        case .standard:
            shouldDrawAfterClaimWindow = true
            phase = .claimingAfterPlay
        case .advancedClaiming:
            drawTurnCard(for: player, events: &events)
            endTurn(events: &events)
        }
        return events
    }

    private mutating func applyClaims(
        _ flagIDs: [FlagID],
        by player: PlayerID
    ) throws -> [GameEvent] {
        let requiredPhase: TurnPhase = configuration.claimingRule == .advancedClaiming
            ? .claimingAtTurnStart
            : .claimingAfterPlay
        guard phase == requiredPhase else {
            throw GameRuleError.actionNotAllowed(action: .declareClaims(flagIDs), phase: phase)
        }

        var uniqueFlags = Set<FlagID>()
        var claimsToApply: [FlagID] = []
        for flagID in flagIDs {
            guard uniqueFlags.insert(flagID).inserted else {
                throw GameRuleError.duplicateClaim(flagID)
            }
            let evaluation = evaluateClaim(on: flagID, by: player)
            if case let .alreadyClaimed(owner)? = evaluation.blockReason {
                throw GameRuleError.flagAlreadyClaimed(flag: flagID, by: owner)
            }
            guard evaluation.isClaimable else {
                throw GameRuleError.flagNotClaimable(flagID)
            }
            claimsToApply.append(flagID)

            // A batch has a defined order. Once this prefix wins, flags after it
            // are neither validated nor claimed: the match has already ended.
            if hasWon(player, additionallyClaiming: claimsToApply) {
                break
            }
        }

        // The game-ending prefix is transactional: no flag changes occur if any
        // declaration before the win is invalid.
        for flagID in claimsToApply {
            flags[flagID.rawValue].claimedBy = player
        }

        var events: [GameEvent] = [.claimsDeclared(player: player, flags: claimsToApply)]
        if hasWon(player) {
            winner = player
            phase = .gameOver
            events.append(.gameWon(player: player))
            return events
        }

        switch configuration.claimingRule {
        case .advancedClaiming:
            phase = .playing
        case .standard:
            if shouldDrawAfterClaimWindow {
                drawTurnCard(for: player, events: &events)
            }
            shouldDrawAfterClaimWindow = false
            endTurn(events: &events)
        }
        return events
    }

    private mutating func applyPass(by player: PlayerID) throws -> [GameEvent] {
        guard phase == .playing else {
            throw GameRuleError.actionNotAllowed(action: .pass, phase: phase)
        }
        guard !hasLegalPlay(for: player) else {
            throw GameRuleError.passWhileLegalMoveExists
        }

        var events: [GameEvent] = [.passed(player: player)]
        switch configuration.claimingRule {
        case .standard:
            shouldDrawAfterClaimWindow = false
            phase = .claimingAfterPlay
        case .advancedClaiming:
            endTurn(events: &events)
        }
        return events
    }

    private mutating func endTurn(events: inout [GameEvent]) {
        currentPlayer = currentPlayer.opponent
        turn += 1
        phase = configuration.claimingRule == .advancedClaiming
            ? .claimingAtTurnStart
            : .playing
        events.append(.turnChanged(player: currentPlayer, turn: turn))
    }

    private func hasWon(
        _ player: PlayerID,
        additionallyClaiming additionalFlags: [FlagID] = []
    ) -> Bool {
        let alreadyClaimed = flags
            .filter { $0.claimedBy == player }
            .map(\.id.rawValue)
        let claimed = Array(Set(alreadyClaimed + additionalFlags.map(\.rawValue))).sorted()
        guard claimed.count >= 3 else { return false }
        if claimed.count >= 5 { return true }

        let claimedSet = Set(claimed)
        return (0 ... 6).contains { start in
            claimedSet.contains(start)
                && claimedSet.contains(start + 1)
                && claimedSet.contains(start + 2)
        }
    }

    private func strongestPubliclyPossibleFormation(
        extending visibleCards: [TroopCard]
    ) -> FormationStrength? {
        let needed = 3 - visibleCards.count
        guard needed > 0 else { return FormationStrength(cards: visibleCards) }

        let battlefieldCards = Set(
            flags.flatMap { flag in
                flag.playerOne.cards + flag.playerTwo.cards
            }
        )
        let candidates = TroopCard.fullDeck.filter { !battlefieldCards.contains($0) }
        guard candidates.count >= needed else { return nil }

        var strongest: FormationStrength?
        func consider(_ additions: [TroopCard]) {
            guard let strength = FormationStrength(cards: visibleCards + additions) else { return }
            if strongest == nil || strength > strongest! {
                strongest = strength
            }
        }

        switch needed {
        case 1:
            for first in candidates {
                consider([first])
            }
        case 2:
            for firstIndex in 0 ..< candidates.count - 1 {
                for secondIndex in firstIndex + 1 ..< candidates.count {
                    consider([candidates[firstIndex], candidates[secondIndex]])
                }
            }
        case 3:
            guard candidates.count >= 3 else { return nil }
            for firstIndex in 0 ..< candidates.count - 2 {
                for secondIndex in firstIndex + 1 ..< candidates.count - 1 {
                    for thirdIndex in secondIndex + 1 ..< candidates.count {
                        consider([
                            candidates[firstIndex],
                            candidates[secondIndex],
                            candidates[thirdIndex],
                        ])
                    }
                }
            }
        default:
            return nil
        }
        return strongest
    }
}

// MARK: - Test support

extension BattleLineGame {
    /// Internal scenario constructor used by the package's rules tests. Keeping it
    /// internal prevents app clients from bypassing normal host initialization.
    internal init(
        testingConfiguration configuration: GameConfiguration,
        dealer: PlayerID = .playerTwo,
        currentPlayer: PlayerID = .playerOne,
        phase: TurnPhase,
        turn: UInt64 = 1,
        version: UInt64 = 0,
        flags: [FlagState],
        deck: [TroopCard] = [],
        playerOneHand: [TroopCard] = [],
        playerTwoHand: [TroopCard] = [],
        lastCompletionOrder: UInt64 = 0,
        shouldDrawAfterClaimWindow: Bool = false,
        winner: PlayerID? = nil,
        log: [GameLogEntry] = []
    ) {
        self.configuration = configuration
        self.dealer = dealer
        self.currentPlayer = currentPlayer
        self.phase = phase
        self.turn = turn
        self.version = version
        self.flags = flags
        self.winner = winner
        self.log = log
        self.deck = deck
        self.playerOneHand = playerOneHand
        self.playerTwoHand = playerTwoHand
        self.lastCompletionOrder = lastCompletionOrder
        self.shouldDrawAfterClaimWindow = shouldDrawAfterClaimWindow
    }
}

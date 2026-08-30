import Foundation

/// Formation precedence is encoded from weakest to strongest for comparison.
public enum FormationKind: Int, CaseIterable, Codable, Sendable, Comparable {
    case host = 0
    case skirmish = 1
    case battalion = 2
    case phalanx = 3
    case wedge = 4

    public static func < (lhs: FormationKind, rhs: FormationKind) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Battle Line compares formation kind first and the sum of card values second.
public struct FormationStrength: Codable, Sendable, Hashable, Comparable {
    public let kind: FormationKind
    public let total: Int

    public init?(cards: [TroopCard]) {
        guard cards.count == 3 else { return nil }

        let values = cards.map(\.value).sorted()
        let colors = Set(cards.map(\.color))
        let sameColor = colors.count == 1
        let sameValue = Set(values).count == 1
        let consecutive = values[1] == values[0] + 1 && values[2] == values[1] + 1

        if sameColor && consecutive {
            kind = .wedge
        } else if sameValue {
            kind = .phalanx
        } else if sameColor {
            kind = .battalion
        } else if consecutive {
            kind = .skirmish
        } else {
            kind = .host
        }
        total = values.reduce(0, +)
    }

    public static func < (lhs: FormationStrength, rhs: FormationStrength) -> Bool {
        if lhs.kind != rhs.kind { return lhs.kind < rhs.kind }
        return lhs.total < rhs.total
    }
}

public enum ClaimBlockReason: Codable, Sendable, Equatable {
    case alreadyClaimed(by: PlayerID)
    case claimantFormationIncomplete
    case opponentFormationWins
    case opponentCanStillBuild(strength: FormationStrength)
}

/// Public-table evidence used by the host when validating a claim.
public struct ClaimEvaluation: Codable, Sendable, Equatable {
    public let flag: FlagID
    public let claimant: PlayerID
    public let claimantStrength: FormationStrength?
    public let strongestPossibleOpponentFormation: FormationStrength?
    public let blockReason: ClaimBlockReason?

    public var isClaimable: Bool { blockReason == nil }

    internal init(
        flag: FlagID,
        claimant: PlayerID,
        claimantStrength: FormationStrength?,
        strongestPossibleOpponentFormation: FormationStrength?,
        blockReason: ClaimBlockReason?
    ) {
        self.flag = flag
        self.claimant = claimant
        self.claimantStrength = claimantStrength
        self.strongestPossibleOpponentFormation = strongestPossibleOpponentFormation
        self.blockReason = blockReason
    }
}

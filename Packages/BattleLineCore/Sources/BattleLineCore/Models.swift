import Foundation

/// The two seats in a Battle Line match.
public enum PlayerID: String, CaseIterable, Codable, Sendable, Hashable {
    case playerOne
    case playerTwo

    public var opponent: PlayerID {
        switch self {
        case .playerOne: .playerTwo
        case .playerTwo: .playerOne
        }
    }
}

/// The six troop suits. Raw values are stable wire values, not localized UI text.
public enum TroopColor: String, CaseIterable, Codable, Sendable, Hashable {
    case red
    case orange
    case yellow
    case green
    case blue
    case purple
}

/// A troop card is its own stable identifier: every color/value pair exists once.
public struct TroopCard: Codable, Sendable, Hashable, Comparable {
    public let color: TroopColor
    public let value: Int

    public init(color: TroopColor, value: Int) throws {
        guard Self.validValues.contains(value) else {
            throw ModelValidationError.invalidTroopValue(value)
        }
        self.color = color
        self.value = value
    }

    internal init(uncheckedColor color: TroopColor, value: Int) {
        self.color = color
        self.value = value
    }

    public static let validValues = 1 ... 10

    public static let fullDeck: [TroopCard] = TroopColor.allCases.flatMap { color in
        validValues.map { TroopCard(uncheckedColor: color, value: $0) }
    }

    public static func < (lhs: TroopCard, rhs: TroopCard) -> Bool {
        if lhs.value != rhs.value { return lhs.value < rhs.value }
        let leftColor = TroopColor.allCases.firstIndex(of: lhs.color) ?? 0
        let rightColor = TroopColor.allCases.firstIndex(of: rhs.color) ?? 0
        return leftColor < rightColor
    }

    private enum CodingKeys: String, CodingKey {
        case color
        case value
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let color = try container.decode(TroopColor.self, forKey: .color)
        let value = try container.decode(Int.self, forKey: .value)
        guard Self.validValues.contains(value) else {
            throw DecodingError.dataCorruptedError(
                forKey: .value,
                in: container,
                debugDescription: "Troop value must be between 1 and 10"
            )
        }
        self.color = color
        self.value = value
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(color, forKey: .color)
        try container.encode(value, forKey: .value)
    }
}

public enum ModelValidationError: Error, Codable, Sendable, Equatable {
    case invalidTroopValue(Int)
    case invalidFlagIndex(Int)
}

/// A zero-based battlefield position. The public initializer enforces 0...8.
public struct FlagID: RawRepresentable, Codable, Sendable, Hashable, Comparable {
    public let rawValue: Int

    public init(rawValue: Int) {
        precondition(Self.validIndices.contains(rawValue), "Flag index must be between 0 and 8")
        self.rawValue = rawValue
    }

    public init(validating rawValue: Int) throws {
        guard Self.validIndices.contains(rawValue) else {
            throw ModelValidationError.invalidFlagIndex(rawValue)
        }
        self.rawValue = rawValue
    }

    internal init(unchecked rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let validIndices = 0 ... 8
    public static let all: [FlagID] = validIndices.map(FlagID.init(unchecked:))

    public static func < (lhs: FlagID, rhs: FlagID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(Int.self)
        guard Self.validIndices.contains(rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Flag index must be between 0 and 8"
            )
        }
        self.rawValue = rawValue
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum ClaimingRule: String, Codable, Sendable, Equatable {
    /// Claims are declared after playing (or passing) and before drawing.
    case standard
    /// Claims are declared only at the beginning of the active player's turn.
    case advancedClaiming
}

public struct GameConfiguration: Codable, Sendable, Equatable {
    public var claimingRule: ClaimingRule

    public init(claimingRule: ClaimingRule = .standard) {
        self.claimingRule = claimingRule
    }
}

public enum TurnPhase: String, Codable, Sendable, Equatable {
    /// The player must declare zero or more claims before continuing.
    case claimingAtTurnStart
    /// The player must play a troop, or pass only when no placement is legal.
    case playing
    /// Standard rules: the player must declare zero or more claims before drawing.
    case claimingAfterPlay
    case gameOver
}

public struct FormationSide: Codable, Sendable, Equatable {
    public internal(set) var cards: [TroopCard]

    /// A monotonically increasing value assigned when the third card is placed.
    /// It resolves equal complete formations in favor of the one completed first.
    public internal(set) var completionOrder: UInt64?

    public init(cards: [TroopCard] = [], completionOrder: UInt64? = nil) {
        precondition(cards.count <= 3, "A formation side has only three slots")
        self.cards = cards
        self.completionOrder = completionOrder
    }

    public var isComplete: Bool { cards.count == 3 }
    public var remainingSlots: Int { 3 - cards.count }

    public var strength: FormationStrength? {
        FormationStrength(cards: cards)
    }
}

public struct FlagState: Codable, Sendable, Equatable {
    public let id: FlagID
    public internal(set) var playerOne: FormationSide
    public internal(set) var playerTwo: FormationSide
    public internal(set) var claimedBy: PlayerID?

    public init(
        id: FlagID,
        playerOne: FormationSide = .init(),
        playerTwo: FormationSide = .init(),
        claimedBy: PlayerID? = nil
    ) {
        self.id = id
        self.playerOne = playerOne
        self.playerTwo = playerTwo
        self.claimedBy = claimedBy
    }

    public func formation(for player: PlayerID) -> FormationSide {
        switch player {
        case .playerOne: playerOne
        case .playerTwo: playerTwo
        }
    }

    internal mutating func updateFormation(
        for player: PlayerID,
        _ body: (inout FormationSide) -> Void
    ) {
        switch player {
        case .playerOne: body(&playerOne)
        case .playerTwo: body(&playerTwo)
        }
    }
}

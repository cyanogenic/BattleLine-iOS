import Foundation

/// Stable, Codable SplitMix64 generator for reproducible matches and tests.
public struct SeededGenerator: RandomNumberGenerator, Codable, Sendable, Equatable {
    public private(set) var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

internal enum DeckShuffler {
    static func shuffled<R: RandomNumberGenerator>(
        _ cards: [TroopCard],
        using generator: inout R
    ) -> [TroopCard] {
        guard cards.count > 1 else { return cards }
        var result = cards
        for upperIndex in stride(from: result.count - 1, through: 1, by: -1) {
            let lowerIndex = uniformIndex(through: upperIndex, using: &generator)
            if lowerIndex != upperIndex {
                result.swapAt(lowerIndex, upperIndex)
            }
        }
        return result
    }

    private static func uniformIndex<R: RandomNumberGenerator>(
        through upperBound: Int,
        using generator: inout R
    ) -> Int {
        let count = UInt64(upperBound + 1)
        // Reject the short tail so every index has exactly the same probability.
        let acceptedCount = UInt64.max - (UInt64.max % count)
        var value = generator.next()
        while value >= acceptedCount {
            value = generator.next()
        }
        return Int(value % count)
    }
}

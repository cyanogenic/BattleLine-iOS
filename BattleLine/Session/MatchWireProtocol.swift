import Foundation

enum MatchWireProtocol {
    static let version = 1
    static let rulesetVersion = 1
}

enum MatchWireKind: String, Codable, Sendable {
    case hostHello
    case joinRequest
    case joinAccepted
    case joinRejected
    case ready
    case actionCommand
    case stateSnapshot
    case commandRejected
    case resumeRequest
    case resign
    case rematchRequest
    case ping
    case pong
}

struct MatchWireEnvelope: Codable, Sendable, Equatable {
    let protocolVersion: Int
    let rulesetVersion: Int
    let matchID: UUID?
    let messageID: UUID
    let kind: MatchWireKind
    let stateVersion: UInt64?
    let payload: Data

    init(
        kind: MatchWireKind,
        matchID: UUID? = nil,
        stateVersion: UInt64? = nil,
        payload: Data = Data(),
        messageID: UUID = UUID()
    ) {
        self.protocolVersion = MatchWireProtocol.version
        self.rulesetVersion = MatchWireProtocol.rulesetVersion
        self.matchID = matchID
        self.messageID = messageID
        self.kind = kind
        self.stateVersion = stateVersion
        self.payload = payload
    }

    func decodePayload<Value: Decodable>(_ type: Value.Type) throws -> Value {
        try MatchWireCoding.decoder.decode(type, from: payload)
    }

    static func carrying<Value: Encodable>(
        _ value: Value,
        kind: MatchWireKind,
        matchID: UUID? = nil,
        stateVersion: UInt64? = nil,
        messageID: UUID = UUID()
    ) throws -> MatchWireEnvelope {
        MatchWireEnvelope(
            kind: kind,
            matchID: matchID,
            stateVersion: stateVersion,
            payload: try MatchWireCoding.encoder.encode(value),
            messageID: messageID
        )
    }
}

enum MatchWireCoding {
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    static var decoder: JSONDecoder {
        JSONDecoder()
    }

    static func encode(_ envelope: MatchWireEnvelope) throws -> Data {
        try encoder.encode(envelope)
    }

    static func decode(_ data: Data) throws -> MatchWireEnvelope {
        let envelope = try decoder.decode(MatchWireEnvelope.self, from: data)
        guard envelope.protocolVersion == MatchWireProtocol.version else {
            throw MatchWireError.unsupportedProtocol(envelope.protocolVersion)
        }
        guard envelope.rulesetVersion == MatchWireProtocol.rulesetVersion else {
            throw MatchWireError.unsupportedRuleset(envelope.rulesetVersion)
        }
        return envelope
    }
}

enum MatchWireError: Error, LocalizedError, Sendable, Equatable {
    case unsupportedProtocol(Int)
    case unsupportedRuleset(Int)
    case unexpectedMessage(MatchWireKind)
    case mismatchedMatch
    case staleState(expected: UInt64, actual: UInt64)
    case malformedPayload

    var errorDescription: String? {
        switch self {
        case .unsupportedProtocol:
            "BattleLine 版本不兼容"
        case .unsupportedRuleset:
            "对局规则版本不兼容"
        case .unexpectedMessage:
            "收到了当前阶段不允许的消息"
        case .mismatchedMatch:
            "消息不属于当前对局"
        case .staleState:
            "对局状态已经更新，请同步后重试"
        case .malformedPayload:
            "对局消息损坏"
        }
    }
}

struct HostHelloPayload: Codable, Sendable, Equatable {
    let hostName: String
    let pairingCode: String
    let advancedClaiming: Bool
}

struct JoinRequestPayload: Codable, Sendable, Equatable {
    let playerName: String
    let clientInstanceID: UUID
    let pairingCode: String
}

struct JoinAcceptedPayload: Codable, Sendable, Equatable {
    let resumeToken: UUID
    let guestSeat: Int
    let hostName: String
    let guestName: String
}

struct RejectionPayload: Codable, Sendable, Equatable {
    let reason: String
}

struct ActionCommandPayload: Codable, Sendable, Equatable {
    let commandID: UUID
    let expectedStateVersion: UInt64
    let encodedAction: Data
}

struct StateSnapshotPayload: Codable, Sendable, Equatable {
    let recipientSeat: Int
    let encodedPlayerView: Data
    let claimableFlagIndices: [Int]
}

struct ResumeRequestPayload: Codable, Sendable, Equatable {
    let resumeToken: UUID
    let lastStateVersion: UInt64
}

import Foundation
import Testing
@testable import BattleLine

struct MatchWireProtocolTests {
    @Test
    func hostHelloRoundTrips() throws {
        let matchID = UUID()
        let payload = HostHelloPayload(
            hostName: "房主",
            pairingCode: "428 193",
            advancedClaiming: true
        )
        let envelope = try MatchWireEnvelope.carrying(
            payload,
            kind: .hostHello,
            matchID: matchID
        )

        let decoded = try MatchWireCoding.decode(MatchWireCoding.encode(envelope))

        #expect(decoded.matchID == matchID)
        #expect(try decoded.decodePayload(HostHelloPayload.self) == payload)
    }

    @Test
    func incompatibleProtocolIsRejected() throws {
        let valid = MatchWireEnvelope(kind: .ping)
        let encoded = try MatchWireCoding.encode(valid)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["protocolVersion"] = 99
        let incompatible = try JSONSerialization.data(withJSONObject: object)

        #expect(throws: MatchWireError.unsupportedProtocol(99)) {
            try MatchWireCoding.decode(incompatible)
        }
    }
}


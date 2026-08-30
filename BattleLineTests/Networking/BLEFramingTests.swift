import Foundation
import XCTest
@testable import BattleLine

final class BLEFramingTests: XCTestCase {
    func testCRC32KnownVector() {
        XCTAssertEqual(
            CRC32.checksum(Data("123456789".utf8)),
            0xCBF4_3926
        )
    }

    func testFragmentationReassemblesOutOfOrderAndSuppressesDuplicateMessage() throws {
        let original = Data((0..<251).map { UInt8($0 % 256) })
        let messageID: UInt32 = 0x1020_3040
        let packets = try BLEFrameCodec.fragment(
            original,
            messageID: messageID,
            maximumPacketLength: 31
        )
        XCTAssertGreaterThan(packets.count, 1)
        XCTAssertTrue(packets.allSatisfy { $0.count <= 31 })

        var reassembler = BLEMessageReassembler(maximumMessageBytes: 1_024)
        var received: Data?

        for packet in packets.reversed() {
            if case let .message(id, payload) = try reassembler.ingest(packet) {
                XCTAssertEqual(id, messageID)
                received = payload
            }
        }

        XCTAssertEqual(received, original)
        XCTAssertEqual(
            try reassembler.ingest(packets[0]),
            .duplicate(messageID: messageID)
        )
    }

    func testAcknowledgementRoundTrip() throws {
        let messageID: UInt32 = 42
        let encoded = BLEFrameCodec.acknowledgement(messageID: messageID)
        XCTAssertEqual(encoded.count, BLEFrameCodec.headerLength)

        var reassembler = BLEMessageReassembler()
        XCTAssertEqual(
            try reassembler.ingest(encoded),
            .acknowledgement(messageID: messageID)
        )
    }

    func testCorruptedPayloadFailsWholeMessageCRC() throws {
        let original = Data("A payload that spans multiple BLE packets.".utf8)
        var packets = try BLEFrameCodec.fragment(
            original,
            messageID: 7,
            maximumPacketLength: 21
        )
        let lastPacketIndex = packets.index(before: packets.endIndex)
        let lastByteIndex = packets[lastPacketIndex].index(before: packets[lastPacketIndex].endIndex)
        packets[lastPacketIndex][lastByteIndex] ^= 0x01

        var reassembler = BLEMessageReassembler(maximumMessageBytes: 1_024)
        for packet in packets.dropLast() {
            XCTAssertEqual(try reassembler.ingest(packet), .incomplete)
        }

        XCTAssertThrowsError(try reassembler.ingest(packets[lastPacketIndex])) { error in
            guard case .checksumMismatch = error as? BLEFrameError else {
                return XCTFail("Expected checksumMismatch, received \(error)")
            }
        }
    }

    func testEmptyPayloadUsesOnePacket() throws {
        let packets = try BLEFrameCodec.fragment(
            Data(),
            messageID: 99,
            maximumPacketLength: 20
        )
        XCTAssertEqual(packets.count, 1)

        var reassembler = BLEMessageReassembler()
        XCTAssertEqual(
            try reassembler.ingest(packets[0]),
            .message(id: 99, payload: Data())
        )
    }
}

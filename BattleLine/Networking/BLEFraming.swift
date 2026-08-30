import Foundation

/// CRC-32/ISO-HDLC, the CRC variant commonly described by the polynomial
/// `0xEDB88320`. It is deliberately implemented without CoreBluetooth so the
/// wire format can be tested on any Swift platform.
public enum CRC32: Sendable {
    public static func checksum(_ data: Data) -> UInt32 {
        var crc = UInt32.max

        for byte in data {
            var value = (crc ^ UInt32(byte)) & 0xFF
            for _ in 0..<8 {
                value = (value & 1) == 1
                    ? (value >> 1) ^ 0xEDB8_8320
                    : value >> 1
            }
            crc = (crc >> 8) ^ value
        }

        return crc ^ UInt32.max
    }
}

public enum BLEPacketKind: UInt8, Sendable {
    case data = 0
    case acknowledgement = 1
}

/// A decoded BattleLine BLE packet.
///
/// Wire header (13 bytes, network byte order):
///
///     version/kind  messageID  chunkIndex  chunkCount  messageCRC32
///          1            4          2           2            4
///
/// The high nibble of the first byte is the protocol version; the low nibble
/// is ``BLEPacketKind``. Acknowledgements have no payload and zeroed chunk and
/// CRC fields. Data packets repeat the CRC of the *whole message* in every
/// chunk, allowing inconsistent or corrupted chunk sets to be rejected.
public struct BLEFrame: Sendable, Equatable {
    public let kind: BLEPacketKind
    public let messageID: UInt32
    public let chunkIndex: UInt16
    public let chunkCount: UInt16
    public let messageCRC32: UInt32
    public let payload: Data

    public init(
        kind: BLEPacketKind,
        messageID: UInt32,
        chunkIndex: UInt16,
        chunkCount: UInt16,
        messageCRC32: UInt32,
        payload: Data
    ) {
        self.kind = kind
        self.messageID = messageID
        self.chunkIndex = chunkIndex
        self.chunkCount = chunkCount
        self.messageCRC32 = messageCRC32
        self.payload = payload
    }
}

public enum BLEFrameError: Error, Sendable, Equatable {
    case packetTooShort(actual: Int)
    case unsupportedVersion(UInt8)
    case unknownPacketKind(UInt8)
    case invalidAcknowledgement
    case invalidChunkIndex(index: UInt16, count: UInt16)
    case packetLimitTooSmall(actual: Int, minimum: Int)
    case tooManyChunks(actual: Int, maximum: Int)
    case inconsistentMessage(messageID: UInt32)
    case messageTooLarge(actual: Int, maximum: Int)
    case tooManyInFlightMessages(maximum: Int)
    case receiveBufferFull(maximum: Int)
    case checksumMismatch(expected: UInt32, actual: UInt32)
}

public enum BLEFrameCodec: Sendable {
    public static let version: UInt8 = 1
    public static let headerLength = 13

    public static func fragment(
        _ message: Data,
        messageID: UInt32,
        maximumPacketLength: Int
    ) throws -> [Data] {
        guard maximumPacketLength > headerLength else {
            throw BLEFrameError.packetLimitTooSmall(
                actual: maximumPacketLength,
                minimum: headerLength + 1
            )
        }

        let maximumPayloadLength = maximumPacketLength - headerLength
        let chunkCount = message.isEmpty
            ? 1
            : ((message.count - 1) / maximumPayloadLength) + 1

        guard chunkCount <= Int(UInt16.max) else {
            throw BLEFrameError.tooManyChunks(
                actual: chunkCount,
                maximum: Int(UInt16.max)
            )
        }

        let crc = CRC32.checksum(message)
        var packets: [Data] = []
        packets.reserveCapacity(chunkCount)

        for chunkIndex in 0..<chunkCount {
            let start = chunkIndex * maximumPayloadLength
            let end = min(start + maximumPayloadLength, message.count)
            let payload = start < end ? message.subdata(in: start..<end) : Data()
            let frame = BLEFrame(
                kind: .data,
                messageID: messageID,
                chunkIndex: UInt16(chunkIndex),
                chunkCount: UInt16(chunkCount),
                messageCRC32: crc,
                payload: payload
            )
            packets.append(encode(frame))
        }

        return packets
    }

    public static func acknowledgement(messageID: UInt32) -> Data {
        encode(
            BLEFrame(
                kind: .acknowledgement,
                messageID: messageID,
                chunkIndex: 0,
                chunkCount: 0,
                messageCRC32: 0,
                payload: Data()
            )
        )
    }

    public static func encode(_ frame: BLEFrame) -> Data {
        var packet = Data(capacity: headerLength + frame.payload.count)
        packet.append((version << 4) | (frame.kind.rawValue & 0x0F))
        append(frame.messageID, to: &packet)
        append(frame.chunkIndex, to: &packet)
        append(frame.chunkCount, to: &packet)
        append(frame.messageCRC32, to: &packet)
        packet.append(frame.payload)
        return packet
    }

    public static func decode(_ packet: Data) throws -> BLEFrame {
        guard packet.count >= headerLength else {
            throw BLEFrameError.packetTooShort(actual: packet.count)
        }

        let bytes = [UInt8](packet)
        let control = bytes[0]
        let packetVersion = control >> 4
        guard packetVersion == version else {
            throw BLEFrameError.unsupportedVersion(packetVersion)
        }

        let rawKind = control & 0x0F
        guard let kind = BLEPacketKind(rawValue: rawKind) else {
            throw BLEFrameError.unknownPacketKind(rawKind)
        }

        let messageID = readUInt32(bytes, at: 1)
        let chunkIndex = readUInt16(bytes, at: 5)
        let chunkCount = readUInt16(bytes, at: 7)
        let crc = readUInt32(bytes, at: 9)
        let payload = Data(bytes.dropFirst(headerLength))

        switch kind {
        case .acknowledgement:
            guard chunkIndex == 0,
                  chunkCount == 0,
                  crc == 0,
                  payload.isEmpty else {
                throw BLEFrameError.invalidAcknowledgement
            }

        case .data:
            guard chunkCount > 0, chunkIndex < chunkCount else {
                throw BLEFrameError.invalidChunkIndex(
                    index: chunkIndex,
                    count: chunkCount
                )
            }
        }

        return BLEFrame(
            kind: kind,
            messageID: messageID,
            chunkIndex: chunkIndex,
            chunkCount: chunkCount,
            messageCRC32: crc,
            payload: payload
        )
    }

    private static func append(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(truncatingIfNeeded: value >> 8))
        data.append(UInt8(truncatingIfNeeded: value))
    }

    private static func append(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(truncatingIfNeeded: value >> 24))
        data.append(UInt8(truncatingIfNeeded: value >> 16))
        data.append(UInt8(truncatingIfNeeded: value >> 8))
        data.append(UInt8(truncatingIfNeeded: value))
    }

    private static func readUInt16(_ bytes: [UInt8], at offset: Int) -> UInt16 {
        (UInt16(bytes[offset]) << 8)
            | UInt16(bytes[offset + 1])
    }

    private static func readUInt32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        (UInt32(bytes[offset]) << 24)
            | (UInt32(bytes[offset + 1]) << 16)
            | (UInt32(bytes[offset + 2]) << 8)
            | UInt32(bytes[offset + 3])
    }
}

public enum BLEReassemblyResult: Sendable, Equatable {
    case incomplete
    case message(id: UInt32, payload: Data)
    case acknowledgement(messageID: UInt32)
    case duplicate(messageID: UInt32)
}

/// Bounded, order-independent message reassembly and duplicate suppression.
/// This value type contains no Apple-framework state and is safe to exercise in
/// normal unit tests.
public struct BLEMessageReassembler: Sendable {
    private struct PartialMessage: Sendable {
        let chunkCount: UInt16
        let checksum: UInt32
        var chunks: [UInt16: Data]
        var receivedByteCount: Int
    }

    public let maximumMessageBytes: Int
    public let maximumBufferedBytes: Int
    public let maximumInFlightMessages: Int
    public let duplicateWindow: Int

    private var partialMessages: [UInt32: PartialMessage] = [:]
    private var bufferedByteCount = 0
    private var completedMessageIDs: Set<UInt32> = []
    private var completionOrder: [UInt32] = []

    public init(
        maximumMessageBytes: Int = 4 * 1_024 * 1_024,
        maximumBufferedBytes: Int? = nil,
        maximumInFlightMessages: Int = 8,
        duplicateWindow: Int = 256
    ) {
        let safeMessageLimit = max(1, maximumMessageBytes)
        self.maximumMessageBytes = safeMessageLimit
        let doubledLimit = safeMessageLimit.multipliedReportingOverflow(by: 2)
        let defaultBufferLimit = doubledLimit.overflow ? Int.max : doubledLimit.partialValue
        self.maximumBufferedBytes = max(
            safeMessageLimit,
            maximumBufferedBytes ?? defaultBufferLimit
        )
        self.maximumInFlightMessages = max(1, maximumInFlightMessages)
        self.duplicateWindow = max(1, duplicateWindow)
    }

    public mutating func ingest(_ packet: Data) throws -> BLEReassemblyResult {
        try ingest(BLEFrameCodec.decode(packet))
    }

    public mutating func ingest(_ frame: BLEFrame) throws -> BLEReassemblyResult {
        if frame.kind == .acknowledgement {
            return .acknowledgement(messageID: frame.messageID)
        }

        guard frame.chunkCount > 0, frame.chunkIndex < frame.chunkCount else {
            throw BLEFrameError.invalidChunkIndex(
                index: frame.chunkIndex,
                count: frame.chunkCount
            )
        }

        if completedMessageIDs.contains(frame.messageID) {
            return .duplicate(messageID: frame.messageID)
        }

        var partial: PartialMessage
        if let existing = partialMessages[frame.messageID] {
            guard existing.chunkCount == frame.chunkCount,
                  existing.checksum == frame.messageCRC32 else {
                discardPartialMessage(id: frame.messageID)
                throw BLEFrameError.inconsistentMessage(messageID: frame.messageID)
            }
            partial = existing
        } else {
            guard partialMessages.count < maximumInFlightMessages else {
                throw BLEFrameError.tooManyInFlightMessages(
                    maximum: maximumInFlightMessages
                )
            }
            partial = PartialMessage(
                chunkCount: frame.chunkCount,
                checksum: frame.messageCRC32,
                chunks: [:],
                receivedByteCount: 0
            )
        }

        // An ATT retry or repeated notification can deliver the same frame
        // more than once. Keep the first copy and wait for missing chunks.
        if partial.chunks[frame.chunkIndex] != nil {
            return .incomplete
        }

        let newMessageSize = partial.receivedByteCount.addingReportingOverflow(
            frame.payload.count
        )
        guard !newMessageSize.overflow,
              newMessageSize.partialValue <= maximumMessageBytes else {
            discardPartialMessage(id: frame.messageID)
            throw BLEFrameError.messageTooLarge(
                actual: newMessageSize.overflow ? Int.max : newMessageSize.partialValue,
                maximum: maximumMessageBytes
            )
        }

        let newBufferedSize = bufferedByteCount.addingReportingOverflow(frame.payload.count)
        guard !newBufferedSize.overflow,
              newBufferedSize.partialValue <= maximumBufferedBytes else {
            discardPartialMessage(id: frame.messageID)
            throw BLEFrameError.receiveBufferFull(maximum: maximumBufferedBytes)
        }

        partial.chunks[frame.chunkIndex] = frame.payload
        partial.receivedByteCount = newMessageSize.partialValue
        bufferedByteCount = newBufferedSize.partialValue
        partialMessages[frame.messageID] = partial

        guard partial.chunks.count == Int(partial.chunkCount) else {
            return .incomplete
        }

        var message = Data(capacity: partial.receivedByteCount)
        for index in 0..<Int(partial.chunkCount) {
            guard let chunk = partial.chunks[UInt16(index)] else {
                return .incomplete
            }
            message.append(chunk)
        }

        let actualChecksum = CRC32.checksum(message)
        discardPartialMessage(id: frame.messageID)
        guard actualChecksum == partial.checksum else {
            throw BLEFrameError.checksumMismatch(
                expected: partial.checksum,
                actual: actualChecksum
            )
        }

        rememberCompletedMessage(frame.messageID)
        return .message(id: frame.messageID, payload: message)
    }

    public mutating func reset() {
        partialMessages.removeAll(keepingCapacity: false)
        completedMessageIDs.removeAll(keepingCapacity: false)
        completionOrder.removeAll(keepingCapacity: false)
        bufferedByteCount = 0
    }

    private mutating func discardPartialMessage(id: UInt32) {
        guard let discarded = partialMessages.removeValue(forKey: id) else {
            return
        }
        bufferedByteCount = max(0, bufferedByteCount - discarded.receivedByteCount)
    }

    private mutating func rememberCompletedMessage(_ messageID: UInt32) {
        completedMessageIDs.insert(messageID)
        completionOrder.append(messageID)

        if completionOrder.count > duplicateWindow {
            let expiredID = completionOrder.removeFirst()
            completedMessageIDs.remove(expiredID)
        }
    }
}

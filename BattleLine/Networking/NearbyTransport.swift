import Foundation

public enum BLENearbyRole: Sendable, Equatable {
    case host
    case join
}

public enum NearbyBluetoothUnavailableReason: String, Sendable, Equatable {
    case poweredOff
    case unauthorized
    case unsupported
    case resetting
    case unknown
}

public enum NearbyConnectionState: Sendable, Equatable {
    case idle
    case waitingForBluetooth
    case advertising
    case scanning
    case connecting(peerID: String)
    case connected(peerID: String)
    case unavailable(NearbyBluetoothUnavailableReason)
    case failed(String)
    case stopped
}

public enum NearbyTransportError: Error, Sendable, Equatable {
    case notStarted
    case notConnected
    case bluetoothUnavailable(NearbyBluetoothUnavailableReason)
    case payloadTooLarge(actual: Int, maximum: Int)
    case framing(BLEFrameError)
    case connectionFailed(String)
    case transmissionFailed(String)
    case acknowledgementTimedOut(messageID: UInt32)
    case cancelled
}

extension NearbyTransportError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notStarted:
            "Nearby transport has not been started."
        case .notConnected:
            "No nearby player is connected."
        case let .bluetoothUnavailable(reason):
            "Bluetooth is unavailable: \(reason.rawValue)."
        case let .payloadTooLarge(actual, maximum):
            "Payload is \(actual) bytes; the maximum is \(maximum) bytes."
        case let .framing(error):
            "Invalid BattleLine BLE packet: \(error)."
        case let .connectionFailed(reason):
            "Bluetooth connection failed: \(reason)"
        case let .transmissionFailed(reason):
            "Bluetooth transmission failed: \(reason)"
        case let .acknowledgementTimedOut(messageID):
            "Message \(messageID) was not acknowledged in time."
        case .cancelled:
            "Bluetooth transmission was cancelled."
        }
    }
}

public enum NearbyTransportEvent: Sendable, Equatable {
    case stateChanged(NearbyConnectionState)
    case received(Data)
    case error(NearbyTransportError)
}

/// Data-only nearby transport API. Game/domain models intentionally do not
/// cross this boundary; callers choose their own deterministic serialization.
@MainActor
public protocol NearbyTransport: AnyObject {
    var role: BLENearbyRole { get }
    var state: NearbyConnectionState { get }
    var events: AsyncStream<NearbyTransportEvent> { get }

    func start()
    func stop()
    func send(_ payload: Data) async throws
}

/// Stable wire identifiers shared by all BattleLine builds using protocol v1.
public enum BLENearbyIdentifiers: Sendable {
    public static let advertisedName = "BattleLine"
    public static let serviceUUID = "B4111E00-7472-4E45-8B1E-BA771E000001"
    public static let receiveCharacteristicUUID = "B4111E00-7472-4E45-8B1E-BA771E000002"
    public static let transmitCharacteristicUUID = "B4111E00-7472-4E45-8B1E-BA771E000003"
}

public struct BLENearbyConfiguration: Sendable, Equatable {
    public var maximumMessageBytes: Int
    public var acknowledgementTimeout: Duration
    public var maximumRetryCount: Int
    public var duplicateWindow: Int

    public init(
        maximumMessageBytes: Int = 4 * 1_024 * 1_024,
        acknowledgementTimeout: Duration = .seconds(15),
        maximumRetryCount: Int = 2,
        duplicateWindow: Int = 256
    ) {
        self.maximumMessageBytes = max(1, maximumMessageBytes)
        self.acknowledgementTimeout = acknowledgementTimeout
        self.maximumRetryCount = max(0, maximumRetryCount)
        self.duplicateWindow = max(1, duplicateWindow)
    }
}

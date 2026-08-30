@preconcurrency import CoreBluetooth
import Foundation

/// Foreground-only, one-peer CoreBluetooth transport.
///
/// The host acts as a GATT peripheral and advertises one fixed service. The
/// joining device acts as the central, writes data/ACK packets to RX using
/// `.withResponse`, and subscribes to TX notifications. Message-level ACKs make
/// `send(_:)` complete only after the remote reassembles and CRC-checks the
/// complete payload.
@MainActor
public final class BLENearbyTransport: NSObject, NearbyTransport {
    public let role: BLENearbyRole
    public private(set) var state: NearbyConnectionState = .idle
    public let events: AsyncStream<NearbyTransportEvent>

    private let configuration: BLENearbyConfiguration
    private let eventContinuation: AsyncStream<NearbyTransportEvent>.Continuation

    private let serviceUUID = CBUUID(string: BLENearbyIdentifiers.serviceUUID)
    private let receiveUUID = CBUUID(string: BLENearbyIdentifiers.receiveCharacteristicUUID)
    private let transmitUUID = CBUUID(string: BLENearbyIdentifiers.transmitCharacteristicUUID)

    private var isStarted = false
    private var peripheralManager: CBPeripheralManager?
    private var centralManager: CBCentralManager?

    // Host-side CoreBluetooth state.
    private var receiveMutableCharacteristic: CBMutableCharacteristic?
    private var transmitMutableCharacteristic: CBMutableCharacteristic?
    private var subscribedCentral: CBCentral?
    private var notificationIsBlocked = false

    // Join-side CoreBluetooth state.
    private var peerPeripheral: CBPeripheral?
    private var receiveCharacteristic: CBCharacteristic?
    private var transmitCharacteristic: CBCharacteristic?
    private var centralWriteInFlight: OutboundPacket?

    private var reassembler: BLEMessageReassembler
    private var outboundPackets: [OutboundPacket] = []
    private var pendingSends: [UInt32: PendingSend] = [:]
    private var timeoutTasks: [UInt32: Task<Void, Never>] = [:]
    private var nextMessageID: UInt32

    private struct OutboundPacket {
        let messageID: UInt32
        let bytes: Data
        let isAcknowledgement: Bool
        let isFinalDataFrame: Bool
    }

    private struct PendingSend {
        let continuation: CheckedContinuation<Void, any Error>
        let frames: [Data]
        var remainingRetries: Int
    }

    public init(
        role: BLENearbyRole,
        configuration: BLENearbyConfiguration = .init()
    ) {
        let stream = AsyncStream<NearbyTransportEvent>.makeStream()
        self.role = role
        self.configuration = configuration
        self.events = stream.stream
        self.eventContinuation = stream.continuation
        self.reassembler = BLEMessageReassembler(
            maximumMessageBytes: configuration.maximumMessageBytes,
            duplicateWindow: configuration.duplicateWindow
        )
        self.nextMessageID = UInt32.random(in: 1...UInt32.max)
        super.init()
    }

    deinit {
        eventContinuation.finish()
    }

    public func start() {
        guard !isStarted else { return }
        isStarted = true
        transition(to: .waitingForBluetooth)

        switch role {
        case .host:
            peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
        case .join:
            centralManager = CBCentralManager(delegate: self, queue: nil)
        }
    }

    public func stop() {
        guard isStarted else {
            transition(to: .stopped)
            return
        }

        isStarted = false

        if let centralManager {
            centralManager.stopScan()
            if let peerPeripheral {
                peerPeripheral.delegate = nil
                centralManager.cancelPeripheralConnection(peerPeripheral)
            }
            centralManager.delegate = nil
        }

        if let peripheralManager {
            peripheralManager.stopAdvertising()
            peripheralManager.removeAllServices()
            peripheralManager.delegate = nil
        }

        centralManager = nil
        peripheralManager = nil
        peerPeripheral = nil
        subscribedCentral = nil
        receiveCharacteristic = nil
        transmitCharacteristic = nil
        receiveMutableCharacteristic = nil
        transmitMutableCharacteristic = nil
        resetSession(error: .cancelled)
        transition(to: .stopped)
    }

    /// Sends one application payload and returns only after the peer has
    /// reassembled it, verified its CRC, and returned a message ACK.
    public func send(_ payload: Data) async throws {
        guard isStarted else {
            throw NearbyTransportError.notStarted
        }
        guard case .connected = state else {
            throw NearbyTransportError.notConnected
        }
        guard payload.count <= configuration.maximumMessageBytes else {
            throw NearbyTransportError.payloadTooLarge(
                actual: payload.count,
                maximum: configuration.maximumMessageBytes
            )
        }

        let packetLength = try maximumPacketLengthForCurrentPeer()
        let messageID = allocateMessageID()
        let frames: [Data]
        do {
            frames = try BLEFrameCodec.fragment(
                payload,
                messageID: messageID,
                maximumPacketLength: packetLength
            )
        } catch let error as BLEFrameError {
            throw NearbyTransportError.framing(error)
        }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, any Error>) in
                pendingSends[messageID] = PendingSend(
                    continuation: continuation,
                    frames: frames,
                    remainingRetries: configuration.maximumRetryCount
                )
                enqueueDataFrames(frames, messageID: messageID)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.failSend(messageID, with: .cancelled)
            }
        }
    }

    private func allocateMessageID() -> UInt32 {
        var candidate = nextMessageID
        while candidate == 0 || pendingSends[candidate] != nil {
            candidate &+= 1
        }
        nextMessageID = candidate &+ 1
        if nextMessageID == 0 {
            nextMessageID = 1
        }
        return candidate
    }

    private func maximumPacketLengthForCurrentPeer() throws -> Int {
        switch role {
        case .host:
            guard let subscribedCentral else {
                throw NearbyTransportError.notConnected
            }
            return subscribedCentral.maximumUpdateValueLength

        case .join:
            guard let peerPeripheral, receiveCharacteristic != nil else {
                throw NearbyTransportError.notConnected
            }
            return peerPeripheral.maximumWriteValueLength(for: .withResponse)
        }
    }

    private func enqueueDataFrames(_ frames: [Data], messageID: UInt32) {
        outboundPackets.append(
            contentsOf: frames.enumerated().map { index, bytes in
                OutboundPacket(
                    messageID: messageID,
                    bytes: bytes,
                    isAcknowledgement: false,
                    isFinalDataFrame: index == frames.count - 1
                )
            }
        )
        drainOutboundPackets()
    }

    private func enqueueAcknowledgement(messageID: UInt32) {
        let packet = OutboundPacket(
            messageID: messageID,
            bytes: BLEFrameCodec.acknowledgement(messageID: messageID),
            isAcknowledgement: true,
            isFinalDataFrame: false
        )

        // ACKs are tiny and latency-sensitive. Reassembly supports out-of-order
        // data, so putting the ACK ahead of queued data cannot corrupt a stream.
        outboundPackets.insert(packet, at: 0)
        drainOutboundPackets()
    }

    private func drainOutboundPackets() {
        guard isStarted else { return }

        switch role {
        case .host:
            drainHostNotifications()
        case .join:
            drainCentralWrites()
        }
    }

    private func drainHostNotifications() {
        guard !notificationIsBlocked,
              let peripheralManager,
              let transmitMutableCharacteristic,
              let subscribedCentral else {
            return
        }

        while let packet = outboundPackets.first {
            let accepted = peripheralManager.updateValue(
                packet.bytes,
                for: transmitMutableCharacteristic,
                onSubscribedCentrals: [subscribedCentral]
            )
            guard accepted else {
                notificationIsBlocked = true
                return
            }
            outboundPackets.removeFirst()
            if packet.isFinalDataFrame {
                scheduleTimeout(for: packet.messageID)
            }
        }
    }

    private func drainCentralWrites() {
        guard centralWriteInFlight == nil,
              let peerPeripheral,
              let receiveCharacteristic,
              let packet = outboundPackets.first else {
            return
        }

        outboundPackets.removeFirst()
        centralWriteInFlight = packet
        peerPeripheral.writeValue(
            packet.bytes,
            for: receiveCharacteristic,
            type: .withResponse
        )
    }

    private func scheduleTimeout(for messageID: UInt32) {
        guard pendingSends[messageID] != nil, timeoutTasks[messageID] == nil else {
            return
        }
        let timeout = configuration.acknowledgementTimeout
        timeoutTasks[messageID] = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: timeout)
            } catch {
                return
            }
            self?.handleAcknowledgementTimeout(messageID: messageID)
        }
    }

    private func handleAcknowledgementTimeout(messageID: UInt32) {
        timeoutTasks.removeValue(forKey: messageID)
        guard var pending = pendingSends[messageID] else { return }

        if pending.remainingRetries > 0 {
            pending.remainingRetries -= 1
            pendingSends[messageID] = pending
            enqueueDataFrames(pending.frames, messageID: messageID)
        } else {
            failSend(
                messageID,
                with: .acknowledgementTimedOut(messageID: messageID)
            )
        }
    }

    private func completeSend(_ messageID: UInt32) {
        timeoutTasks.removeValue(forKey: messageID)?.cancel()
        pendingSends.removeValue(forKey: messageID)?.continuation.resume()
    }

    private func failSend(_ messageID: UInt32, with error: NearbyTransportError) {
        timeoutTasks.removeValue(forKey: messageID)?.cancel()
        outboundPackets.removeAll {
            $0.messageID == messageID && !$0.isAcknowledgement
        }
        pendingSends.removeValue(forKey: messageID)?.continuation.resume(throwing: error)
    }

    private func failAllSends(with error: NearbyTransportError) {
        let continuations = pendingSends.values.map(\.continuation)
        pendingSends.removeAll(keepingCapacity: false)
        timeoutTasks.values.forEach { $0.cancel() }
        timeoutTasks.removeAll(keepingCapacity: false)
        continuations.forEach { $0.resume(throwing: error) }
    }

    @discardableResult
    private func handleIncomingPacket(_ bytes: Data) -> Bool {
        do {
            switch try reassembler.ingest(bytes) {
            case .incomplete:
                break
            case let .message(id, payload):
                enqueueAcknowledgement(messageID: id)
                eventContinuation.yield(.received(payload))
            case let .duplicate(messageID):
                // The original ACK may have been lost. Do not redeliver the
                // application payload, but make the sender whole again.
                enqueueAcknowledgement(messageID: messageID)
            case let .acknowledgement(messageID):
                completeSend(messageID)
            }
            return true
        } catch let error as BLEFrameError {
            emit(error: .framing(error))
            return false
        } catch {
            emit(error: .transmissionFailed(String(describing: error)))
            return false
        }
    }

    private func transition(to newState: NearbyConnectionState) {
        guard state != newState else { return }
        state = newState
        eventContinuation.yield(.stateChanged(newState))
    }

    private func emit(error: NearbyTransportError) {
        eventContinuation.yield(.error(error))
    }

    private func resetSession(error: NearbyTransportError) {
        reassembler.reset()
        outboundPackets.removeAll(keepingCapacity: false)
        centralWriteInFlight = nil
        notificationIsBlocked = false
        failAllSends(with: error)
    }

    private func unavailableReason(for state: CBManagerState) -> NearbyBluetoothUnavailableReason {
        switch state {
        case .poweredOff:
            .poweredOff
        case .unauthorized:
            .unauthorized
        case .unsupported:
            .unsupported
        case .resetting:
            .resetting
        case .unknown, .poweredOn:
            .unknown
        @unknown default:
            .unknown
        }
    }
}

// MARK: - Host / GATT peripheral

extension BLENearbyTransport: @preconcurrency CBPeripheralManagerDelegate {
    public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        guard isStarted, role == .host else { return }

        guard peripheral.state == .poweredOn else {
            peripheral.stopAdvertising()
            peripheral.removeAllServices()
            receiveMutableCharacteristic = nil
            transmitMutableCharacteristic = nil
            subscribedCentral = nil
            resetSession(error: .bluetoothUnavailable(unavailableReason(for: peripheral.state)))
            transition(to: .unavailable(unavailableReason(for: peripheral.state)))
            return
        }

        configurePeripheralService(using: peripheral)
    }

    private func configurePeripheralService(using manager: CBPeripheralManager) {
        manager.stopAdvertising()
        manager.removeAllServices()

        let receive = CBMutableCharacteristic(
            type: receiveUUID,
            properties: [.write],
            value: nil,
            permissions: [.writeable]
        )
        let transmit = CBMutableCharacteristic(
            type: transmitUUID,
            properties: [.notify],
            value: nil,
            permissions: [.readable]
        )
        let service = CBMutableService(type: serviceUUID, primary: true)
        service.characteristics = [receive, transmit]

        receiveMutableCharacteristic = receive
        transmitMutableCharacteristic = transmit
        manager.add(service)
    }

    public func peripheralManager(
        _ peripheral: CBPeripheralManager,
        didAdd service: CBService,
        error: (any Error)?
    ) {
        guard isStarted, role == .host, service.uuid == serviceUUID else { return }

        if let error {
            let transportError = NearbyTransportError.connectionFailed(
                String(describing: error)
            )
            emit(error: transportError)
            transition(to: .failed(transportError.localizedDescription))
            return
        }

        startAdvertising(using: peripheral)
    }

    public func peripheralManagerDidStartAdvertising(
        _ peripheral: CBPeripheralManager,
        error: (any Error)?
    ) {
        guard isStarted, role == .host else { return }

        if let error {
            let transportError = NearbyTransportError.connectionFailed(
                String(describing: error)
            )
            emit(error: transportError)
            transition(to: .failed(transportError.localizedDescription))
        } else if subscribedCentral == nil {
            transition(to: .advertising)
        }
    }

    public func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didSubscribeTo characteristic: CBCharacteristic
    ) {
        guard isStarted,
              role == .host,
              characteristic.uuid == transmitUUID else {
            return
        }

        // v1 is intentionally a two-player, one-peer transport. Additional
        // subscribers receive no targeted notifications and their writes are
        // rejected below.
        guard subscribedCentral == nil || subscribedCentral?.identifier == central.identifier else {
            return
        }

        subscribedCentral = central
        peripheral.stopAdvertising()
        notificationIsBlocked = false
        transition(to: .connected(peerID: central.identifier.uuidString))
        drainHostNotifications()
    }

    public func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didUnsubscribeFrom characteristic: CBCharacteristic
    ) {
        guard role == .host,
              characteristic.uuid == transmitUUID,
              subscribedCentral?.identifier == central.identifier else {
            return
        }

        subscribedCentral = nil
        resetSession(
            error: .connectionFailed("The nearby player disconnected.")
        )
        if isStarted, peripheral.state == .poweredOn {
            transition(to: .advertising)
            startAdvertising(using: peripheral)
        }
    }

    public func peripheralManager(
        _ peripheral: CBPeripheralManager,
        didReceiveWrite requests: [CBATTRequest]
    ) {
        for request in requests {
            guard request.characteristic.uuid == receiveUUID else {
                peripheral.respond(to: request, withResult: .writeNotPermitted)
                continue
            }
            guard request.offset == 0 else {
                peripheral.respond(to: request, withResult: .invalidOffset)
                continue
            }
            guard let subscribedCentral,
                  subscribedCentral.identifier == request.central.identifier else {
                peripheral.respond(to: request, withResult: .insufficientAuthorization)
                continue
            }
            guard let value = request.value else {
                peripheral.respond(to: request, withResult: .invalidAttributeValueLength)
                continue
            }

            let wasAccepted = handleIncomingPacket(value)
            peripheral.respond(
                to: request,
                withResult: wasAccepted ? .success : .invalidPdu
            )
        }
    }

    public func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        guard isStarted, role == .host else { return }
        notificationIsBlocked = false
        drainHostNotifications()
    }

    private func startAdvertising(using peripheral: CBPeripheralManager) {
        guard isStarted, role == .host, subscribedCentral == nil else { return }
        peripheral.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [serviceUUID],
            CBAdvertisementDataLocalNameKey: BLENearbyIdentifiers.advertisedName,
        ])
    }
}

// MARK: - Join / GATT central

extension BLENearbyTransport: @preconcurrency CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard isStarted, role == .join else { return }

        guard central.state == .poweredOn else {
            central.stopScan()
            if let peerPeripheral {
                central.cancelPeripheralConnection(peerPeripheral)
            }
            peerPeripheral = nil
            receiveCharacteristic = nil
            transmitCharacteristic = nil
            resetSession(error: .bluetoothUnavailable(unavailableReason(for: central.state)))
            transition(to: .unavailable(unavailableReason(for: central.state)))
            return
        }

        beginScanning(using: central)
    }

    private func beginScanning(using central: CBCentralManager) {
        guard isStarted, role == .join, peerPeripheral == nil else { return }
        transition(to: .scanning)
        central.scanForPeripherals(
            withServices: [serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard isStarted, role == .join, peerPeripheral == nil else { return }

        central.stopScan()
        peerPeripheral = peripheral
        peripheral.delegate = self
        transition(to: .connecting(peerID: peripheral.identifier.uuidString))
        central.connect(peripheral)
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard isStarted,
              role == .join,
              peerPeripheral?.identifier == peripheral.identifier else {
            return
        }
        peripheral.discoverServices([serviceUUID])
    }

    public func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: (any Error)?
    ) {
        guard peerPeripheral?.identifier == peripheral.identifier else { return }

        let reason = error.map(String.init(describing:)) ?? "Unknown connection error."
        emit(error: .connectionFailed(reason))
        peripheral.delegate = nil
        peerPeripheral = nil
        receiveCharacteristic = nil
        transmitCharacteristic = nil
        resetSession(error: .connectionFailed(reason))
        if isStarted, central.state == .poweredOn {
            beginScanning(using: central)
        }
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: (any Error)?
    ) {
        guard peerPeripheral?.identifier == peripheral.identifier else { return }

        let reason = error.map(String.init(describing:)) ?? "The nearby player disconnected."
        peripheral.delegate = nil
        peerPeripheral = nil
        receiveCharacteristic = nil
        transmitCharacteristic = nil
        resetSession(error: .connectionFailed(reason))
        emit(error: .connectionFailed(reason))
        if isStarted, central.state == .poweredOn {
            beginScanning(using: central)
        }
    }

    private func cancelCurrentConnection(with error: NearbyTransportError) {
        emit(error: error)
        guard let centralManager, let peerPeripheral else { return }
        centralManager.cancelPeripheralConnection(peerPeripheral)
    }
}

extension BLENearbyTransport: @preconcurrency CBPeripheralDelegate {
    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverServices error: (any Error)?
    ) {
        guard peerPeripheral?.identifier == peripheral.identifier else { return }

        if let error {
            cancelCurrentConnection(with: .connectionFailed(String(describing: error)))
            return
        }
        guard let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else {
            cancelCurrentConnection(with: .connectionFailed("BattleLine BLE service was not found."))
            return
        }
        peripheral.discoverCharacteristics([receiveUUID, transmitUUID], for: service)
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: (any Error)?
    ) {
        guard peerPeripheral?.identifier == peripheral.identifier,
              service.uuid == serviceUUID else {
            return
        }

        if let error {
            cancelCurrentConnection(with: .connectionFailed(String(describing: error)))
            return
        }

        receiveCharacteristic = service.characteristics?.first { $0.uuid == receiveUUID }
        transmitCharacteristic = service.characteristics?.first { $0.uuid == transmitUUID }
        guard receiveCharacteristic != nil, let transmitCharacteristic else {
            cancelCurrentConnection(
                with: .connectionFailed("BattleLine BLE characteristics were not found.")
            )
            return
        }

        peripheral.setNotifyValue(true, for: transmitCharacteristic)
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: (any Error)?
    ) {
        guard peerPeripheral?.identifier == peripheral.identifier,
              characteristic.uuid == transmitUUID else {
            return
        }

        if let error {
            cancelCurrentConnection(with: .connectionFailed(String(describing: error)))
            return
        }
        guard characteristic.isNotifying else {
            cancelCurrentConnection(
                with: .connectionFailed("BattleLine BLE notifications were disabled.")
            )
            return
        }

        transition(to: .connected(peerID: peripheral.identifier.uuidString))
        drainCentralWrites()
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: (any Error)?
    ) {
        guard peerPeripheral?.identifier == peripheral.identifier,
              characteristic.uuid == transmitUUID else {
            return
        }

        if let error {
            emit(error: .transmissionFailed(String(describing: error)))
            return
        }
        guard let value = characteristic.value else {
            emit(error: .transmissionFailed("A notification contained no data."))
            return
        }
        handleIncomingPacket(value)
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: (any Error)?
    ) {
        guard peerPeripheral?.identifier == peripheral.identifier,
              characteristic.uuid == receiveUUID,
              let completedPacket = centralWriteInFlight else {
            return
        }

        centralWriteInFlight = nil
        if let error {
            let transportError = NearbyTransportError.transmissionFailed(
                String(describing: error)
            )
            if completedPacket.isAcknowledgement {
                emit(error: transportError)
            } else {
                failSend(completedPacket.messageID, with: transportError)
            }
        } else if completedPacket.isFinalDataFrame {
            scheduleTimeout(for: completedPacket.messageID)
        }
        drainCentralWrites()
    }
}

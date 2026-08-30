import BattleLineCore
import Foundation
import Observation

struct NearbyRoomPresentation: Identifiable, Hashable, Sendable {
    let id: UUID
    let hostName: String
    let pairingCode: String
    let advancedClaiming: Bool
}

enum NearbyMatchRole: String, Codable, Sendable {
    case host
    case guest
}

enum NearbyMatchStage: Equatable, Sendable {
    case idle
    case startingBluetooth
    case advertising
    case scanning
    case connecting
    case roomFound
    case awaitingHostApproval
    case awaitingHostDecision
    case awaitingSnapshot
    case reconnecting
    case active
    case unavailable(String)
    case failed(String)
}

@MainActor
@Observable
final class NearbyMatchCoordinator {
    typealias TransportFactory = (BLENearbyRole) -> any NearbyTransport

    var stage: NearbyMatchStage = .idle
    var role: NearbyMatchRole?
    var discoveredRoom: NearbyRoomPresentation?
    var pendingGuestName: String?
    var localPlayerName = "玩家"
    var opponentName = "等待加入"
    var pairingCode = "••• •••"
    var advancedClaiming = false
    var statusMessage: String?

    @ObservationIgnored
    var onMatchReady: (() -> Void)?

    private let matchModel: MatchViewModel
    private let transportFactory: TransportFactory
    private let persistence: NearbyMatchPersistence
    private let clientInstanceID = UUID()

    private var transport: (any NearbyTransport)?
    private var eventTask: Task<Void, Never>?
    private var game: BattleLineGame?
    private var latestGuestView: PlayerView?
    private var latestGuestClaimableFlagIndices: [Int] = []
    private var matchID: UUID?
    private var resumeToken: UUID?
    private var localSeat: PlayerID?
    private var processedCommandIDs: Set<UUID> = []
    private var hostSetup: MatchSetupDraft?
    private var sessionTerminated = false

    init(
        matchModel: MatchViewModel,
        transportFactory: @escaping TransportFactory = { role in
            BLENearbyTransport(role: role)
        },
        persistence: NearbyMatchPersistence = NearbyMatchPersistence()
    ) {
        self.matchModel = matchModel
        self.transportFactory = transportFactory
        self.persistence = persistence
        matchModel.setActionHandler { [weak self] action in
            self?.submit(action)
        }
        restorePersistedSession()
    }

    var canResumeCurrentSession: Bool {
        !sessionTerminated && matchID != nil && (game != nil || latestGuestView != nil)
    }

    var isHost: Bool { role == .host }

    func startHosting(setup: MatchSetupDraft) {
        resetForNewSession()
        role = .host
        hostSetup = setup
        localPlayerName = setup.playerName.trimmingCharacters(in: .whitespacesAndNewlines)
        opponentName = "等待加入"
        advancedClaiming = setup.advancedClaiming
        pairingCode = Self.makePairingCode()
        matchID = UUID()
        localSeat = .playerOne
        stage = .startingBluetooth
        matchModel.prepareForHost(name: localPlayerName, code: pairingCode)
        startTransport(role: .host)
    }

    func startJoining(playerName: String) {
        resetForNewSession()
        role = .guest
        localPlayerName = Self.normalizedPlayerName(playerName, fallback: "加入者")
        opponentName = "正在寻找房主"
        stage = .startingBluetooth
        matchModel.prepareForGuest(name: localPlayerName)
        startTransport(role: .join)
    }

    func updateJoiningPlayerName(_ name: String) {
        guard role == .guest, stage != .active else { return }
        localPlayerName = name
        matchModel.localPlayerName = name
    }

    func requestToJoinDiscoveredRoom() {
        guard role == .guest,
              stage == .roomFound,
              let room = discoveredRoom,
              matchID == room.id
        else { return }

        localPlayerName = Self.normalizedPlayerName(localPlayerName, fallback: "加入者")
        stage = .awaitingHostDecision
        statusMessage = nil
        let request = JoinRequestPayload(
            playerName: localPlayerName,
            clientInstanceID: clientInstanceID,
            pairingCode: room.pairingCode
        )
        sendInTask(
            try? MatchWireEnvelope.carrying(
                request,
                kind: .joinRequest,
                matchID: room.id
            )
        )
    }

    func approvePendingGuest() {
        guard role == .host,
              stage == .awaitingHostApproval,
              let pendingGuestName,
              let matchID,
              let setup = hostSetup,
              game == nil
        else { return }

        let token = UUID()
        let seed = UInt64.random(in: UInt64.min ... UInt64.max)
        let dealer: PlayerID = Bool.random() ? .playerOne : .playerTwo
        let configuration = GameConfiguration(
            claimingRule: setup.advancedClaiming ? .advancedClaiming : .standard
        )
        let newGame = BattleLineGame(
            configuration: configuration,
            dealer: dealer,
            seed: seed
        )

        game = newGame
        resumeToken = token
        opponentName = pendingGuestName
        self.pendingGuestName = nil
        processedCommandIDs = []
        stage = .active
        presentHostView()
        onMatchReady?()

        let accepted = JoinAcceptedPayload(
            resumeToken: token,
            guestSeat: Self.seatNumber(for: .playerTwo),
            hostName: localPlayerName,
            guestName: pendingGuestName
        )
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.send(
                    .carrying(
                        accepted,
                        kind: .joinAccepted,
                        matchID: matchID,
                        stateVersion: newGame.version
                    )
                )
                try await self.sendGuestSnapshot()
            } catch {
                self.handleSendFailure(error)
            }
        }
    }

    func rejectPendingGuest() {
        guard role == .host, stage == .awaitingHostApproval else { return }
        pendingGuestName = nil
        stage = .advertising
        let envelope = try? MatchWireEnvelope.carrying(
            RejectionPayload(reason: "房主没有接受本次加入请求"),
            kind: .joinRejected,
            matchID: matchID
        )
        sendInTask(envelope)
    }

    func resignCurrentMatch() {
        guard stage == .active,
              !sessionTerminated,
              matchModel.phase != .finished(winner: .player),
              matchModel.phase != .finished(winner: .opponent)
        else { return }

        sessionTerminated = true
        matchModel.phase = .finished(winner: .opponent)
        matchModel.notice = "你已认输，本局结束"
        persistence.clear()
        sendInTask(MatchWireEnvelope(kind: .resign, matchID: matchID))
    }

    func pauseAndReturnHome() {
        stopTransport()
        if canResumeCurrentSession {
            persistSession()
            stage = .idle
            matchModel.markPaused("对局已保留，可从首页继续")
        } else {
            stage = .idle
            matchModel.disconnect()
        }
    }

    @discardableResult
    func resumeCurrentSession() -> NearbyMatchRole? {
        guard let role, canResumeCurrentSession else { return nil }
        statusMessage = nil
        if game?.winner != nil || latestGuestView?.winner != nil {
            stage = .active
            return role
        }
        stage = .reconnecting
        matchModel.markPaused("正在重新连接附近的对手")
        startTransport(role: role == .host ? .host : .join)
        return role
    }

    func abandonCurrentSession() {
        stopTransport()
        game = nil
        latestGuestView = nil
        latestGuestClaimableFlagIndices = []
        matchID = nil
        resumeToken = nil
        localSeat = nil
        processedCommandIDs = []
        hostSetup = nil
        sessionTerminated = false
        role = nil
        discoveredRoom = nil
        pendingGuestName = nil
        stage = .idle
        statusMessage = nil
        persistence.clear()
        matchModel.disconnect()
    }

    func retryBluetooth() {
        guard let role else { return }
        stopTransport()
        statusMessage = nil
        stage = canResumeCurrentSession ? .reconnecting : .startingBluetooth
        startTransport(role: role == .host ? .host : .join)
    }

    private func submit(_ action: GameAction) {
        guard stage == .active,
              let localSeat,
              let matchID
        else {
            matchModel.showError("蓝牙尚未连接，当前不能操作")
            return
        }

        switch role {
        case .host:
            guard var game else {
                matchModel.showError("房主对局状态不可用")
                return
            }
            do {
                try game.apply(
                    GameCommand(
                        actor: localSeat,
                        expectedVersion: game.version,
                        action: action
                    )
                )
                self.game = game
                presentHostView()
                Task { [weak self] in
                    do {
                        try await self?.sendGuestSnapshot()
                    } catch {
                        self?.handleSendFailure(error)
                    }
                }
            } catch {
                matchModel.showError(Self.ruleErrorMessage(error))
            }

        case .guest:
            let commandID = UUID()
            do {
                let payload = ActionCommandPayload(
                    commandID: commandID,
                    expectedStateVersion: matchModel.stateVersion,
                    encodedAction: try MatchWireCoding.encoder.encode(action)
                )
                let envelope = try MatchWireEnvelope.carrying(
                    payload,
                    kind: .actionCommand,
                    matchID: matchID,
                    stateVersion: matchModel.stateVersion
                )
                sendInTask(envelope)
            } catch {
                matchModel.showError("无法编码这次操作，请重试")
            }

        case nil:
            matchModel.showError("附近对局尚未建立")
        }
    }

    private func startTransport(role transportRole: BLENearbyRole) {
        stopTransport()
        let transport = transportFactory(transportRole)
        self.transport = transport
        let events = transport.events
        eventTask = Task { [weak self] in
            for await event in events {
                guard !Task.isCancelled, let self else { return }
                self.handle(event)
            }
        }
        transport.start()
    }

    private func stopTransport() {
        eventTask?.cancel()
        eventTask = nil
        transport?.stop()
        transport = nil
    }

    private func resetForNewSession() {
        stopTransport()
        game = nil
        latestGuestView = nil
        latestGuestClaimableFlagIndices = []
        matchID = nil
        resumeToken = nil
        localSeat = nil
        processedCommandIDs = []
        hostSetup = nil
        sessionTerminated = false
        role = nil
        discoveredRoom = nil
        pendingGuestName = nil
        statusMessage = nil
        persistence.clear()
    }

    private func handle(_ event: NearbyTransportEvent) {
        switch event {
        case let .stateChanged(state):
            handleTransportState(state)
        case let .received(data):
            handleReceivedData(data)
        case let .error(error):
            handleTransportError(error)
        }
    }

    private func handleTransportState(_ state: NearbyConnectionState) {
        switch state {
        case .idle, .waitingForBluetooth:
            if !canResumeCurrentSession { stage = .startingBluetooth }

        case .advertising:
            if game != nil {
                stage = .reconnecting
                matchModel.markPaused("对手已断开，正在等待蓝牙重连")
            } else {
                stage = .advertising
            }

        case .scanning:
            discoveredRoom = nil
            if latestGuestView != nil {
                stage = .reconnecting
                matchModel.markPaused("与房主断开，正在自动重新扫描")
            } else {
                stage = .scanning
            }

        case .connecting:
            stage = canResumeCurrentSession ? .reconnecting : .connecting

        case .connected:
            matchModel.markConnected()
            if role == .host {
                stage = game == nil ? .connecting : .reconnecting
                sendHostHello()
            } else if latestGuestView != nil {
                stage = .reconnecting
            } else {
                stage = .connecting
            }

        case let .unavailable(reason):
            let explanation = Self.bluetoothExplanation(reason)
            stage = .unavailable(explanation)
            if canResumeCurrentSession { matchModel.markPaused(explanation) }

        case let .failed(message):
            stage = .failed(message)
            if canResumeCurrentSession { matchModel.markPaused(message) }

        case .stopped:
            break
        }
    }

    private func handleTransportError(_ error: NearbyTransportError) {
        switch error {
        case .cancelled:
            break
        case .connectionFailed:
            if canResumeCurrentSession {
                matchModel.markPaused("蓝牙连接中断，正在自动重连")
            }
        default:
            statusMessage = error.localizedDescription
            if canResumeCurrentSession {
                matchModel.showError(error.localizedDescription)
            }
        }
    }

    private func handleReceivedData(_ data: Data) {
        do {
            let envelope = try MatchWireCoding.decode(data)
            try validateMatchIdentity(for: envelope)
            switch role {
            case .host:
                try handleHostEnvelope(envelope)
            case .guest:
                try handleGuestEnvelope(envelope)
            case nil:
                throw MatchWireError.unexpectedMessage(envelope.kind)
            }
        } catch {
            statusMessage = (error as? LocalizedError)?.errorDescription
                ?? "收到了无法解析的附近对局消息"
        }
    }

    private func validateMatchIdentity(for envelope: MatchWireEnvelope) throws {
        if envelope.kind == .hostHello, role == .guest {
            return
        }
        guard envelope.matchID == matchID else {
            throw MatchWireError.mismatchedMatch
        }
    }

    private func handleHostEnvelope(_ envelope: MatchWireEnvelope) throws {
        switch envelope.kind {
        case .joinRequest:
            guard game == nil else {
                sendInTask(
                    try? .carrying(
                        RejectionPayload(reason: "这局对战已经开始"),
                        kind: .joinRejected,
                        matchID: matchID
                    )
                )
                return
            }
            let request = try envelope.decodePayload(JoinRequestPayload.self)
            guard request.pairingCode == pairingCode else {
                sendInTask(
                    try? .carrying(
                        RejectionPayload(reason: "配对码不一致，请重新扫描"),
                        kind: .joinRejected,
                        matchID: matchID
                    )
                )
                return
            }
            pendingGuestName = Self.normalizedPlayerName(request.playerName, fallback: "加入者")
            stage = .awaitingHostApproval

        case .actionCommand:
            try handleGuestAction(envelope)

        case .resumeRequest:
            let request = try envelope.decodePayload(ResumeRequestPayload.self)
            guard game != nil, request.resumeToken == resumeToken else {
                sendInTask(
                    try? .carrying(
                        RejectionPayload(reason: "无法恢复这局对战"),
                        kind: .joinRejected,
                        matchID: matchID
                    )
                )
                return
            }
            stage = .active
            matchModel.markConnected()
            onMatchReady?()
            Task { [weak self] in
                do {
                    try await self?.sendGuestSnapshot()
                } catch {
                    self?.handleSendFailure(error)
                }
            }

        case .ping:
            sendInTask(MatchWireEnvelope(kind: .pong, matchID: matchID))

        case .resign:
            finishBecauseOpponentResigned()

        default:
            throw MatchWireError.unexpectedMessage(envelope.kind)
        }
    }

    private func handleGuestEnvelope(_ envelope: MatchWireEnvelope) throws {
        switch envelope.kind {
        case .hostHello:
            let hello = try envelope.decodePayload(HostHelloPayload.self)
            guard let roomID = envelope.matchID else {
                throw MatchWireError.malformedPayload
            }

            if resumeToken != nil,
               latestGuestView != nil,
               let expectedMatchID = matchID,
               expectedMatchID != roomID {
                let explanation = "发现了另一局 BattleLine；请让原房主开始广播后再重试。"
                statusMessage = explanation
                stage = .failed(explanation)
                return
            }

            matchID = roomID
            opponentName = hello.hostName
            pairingCode = hello.pairingCode
            advancedClaiming = hello.advancedClaiming
            matchModel.opponentName = hello.hostName
            matchModel.pairingCode = hello.pairingCode

            if resumeToken != nil, latestGuestView != nil {
                stage = .reconnecting
                sendResumeRequest()
            } else {
                discoveredRoom = NearbyRoomPresentation(
                    id: roomID,
                    hostName: hello.hostName,
                    pairingCode: hello.pairingCode,
                    advancedClaiming: hello.advancedClaiming
                )
                stage = .roomFound
            }

        case .joinAccepted:
            let accepted = try envelope.decodePayload(JoinAcceptedPayload.self)
            guard let seat = Self.playerID(for: accepted.guestSeat), seat == .playerTwo else {
                throw MatchWireError.malformedPayload
            }
            resumeToken = accepted.resumeToken
            localSeat = seat
            localPlayerName = accepted.guestName
            opponentName = accepted.hostName
            stage = .awaitingSnapshot

        case .joinRejected:
            let rejection = try envelope.decodePayload(RejectionPayload.self)
            statusMessage = rejection.reason
            stage = discoveredRoom == nil ? .scanning : .roomFound
            matchModel.isSubmitting = false

        case .stateSnapshot:
            let snapshot = try envelope.decodePayload(StateSnapshotPayload.self)
            guard let localSeat,
                  snapshot.recipientSeat == Self.seatNumber(for: localSeat)
            else { throw MatchWireError.malformedPayload }
            let view = try MatchWireCoding.decoder.decode(
                PlayerView.self,
                from: snapshot.encodedPlayerView
            )
            guard view.viewer == localSeat else { throw MatchWireError.malformedPayload }
            if let latestGuestView, view.version < latestGuestView.version { return }
            self.latestGuestView = view
            latestGuestClaimableFlagIndices = snapshot.claimableFlagIndices
            matchModel.update(
                from: view,
                claimableFlagIndices: snapshot.claimableFlagIndices,
                localName: localPlayerName,
                opponentName: opponentName
            )
            matchModel.markConnected()
            stage = .active
            statusMessage = nil
            persistSession()
            onMatchReady?()

        case .commandRejected:
            let rejection = try envelope.decodePayload(RejectionPayload.self)
            matchModel.showError(rejection.reason)

        case .ping:
            sendInTask(MatchWireEnvelope(kind: .pong, matchID: matchID))

        case .resign:
            finishBecauseOpponentResigned()

        case .pong:
            break

        default:
            throw MatchWireError.unexpectedMessage(envelope.kind)
        }
    }

    private func handleGuestAction(_ envelope: MatchWireEnvelope) throws {
        guard var game else {
            throw MatchWireError.unexpectedMessage(.actionCommand)
        }
        let payload = try envelope.decodePayload(ActionCommandPayload.self)

        if processedCommandIDs.contains(payload.commandID) {
            Task { [weak self] in try? await self?.sendGuestSnapshot() }
            return
        }

        let action: GameAction
        do {
            action = try MatchWireCoding.decoder.decode(GameAction.self, from: payload.encodedAction)
        } catch {
            throw MatchWireError.malformedPayload
        }

        do {
            try game.apply(
                GameCommand(
                    actor: .playerTwo,
                    expectedVersion: payload.expectedStateVersion,
                    action: action
                )
            )
            self.game = game
            processedCommandIDs.insert(payload.commandID)
            presentHostView()
            Task { [weak self] in
                do {
                    try await self?.sendGuestSnapshot()
                } catch {
                    self?.handleSendFailure(error)
                }
            }
        } catch {
            let message = Self.ruleErrorMessage(error)
            Task { [weak self] in
                guard let self else { return }
                do {
                    try await self.sendGuestSnapshot()
                    try await self.send(
                        .carrying(
                            RejectionPayload(reason: message),
                            kind: .commandRejected,
                            matchID: self.matchID,
                            stateVersion: self.game?.version
                        )
                    )
                } catch {
                    self.handleSendFailure(error)
                }
            }
        }
    }

    private func sendHostHello() {
        guard role == .host, let matchID else { return }
        let selectedAdvancedRule = game?.configuration.claimingRule == .advancedClaiming
            || hostSetup?.advancedClaiming == true
        let payload = HostHelloPayload(
            hostName: localPlayerName,
            pairingCode: pairingCode,
            advancedClaiming: selectedAdvancedRule
        )
        sendInTask(
            try? .carrying(
                payload,
                kind: .hostHello,
                matchID: matchID,
                stateVersion: game?.version
            )
        )
    }

    private func sendResumeRequest() {
        guard let matchID, let resumeToken, let latestGuestView else { return }
        let request = ResumeRequestPayload(
            resumeToken: resumeToken,
            lastStateVersion: latestGuestView.version
        )
        sendInTask(
            try? .carrying(
                request,
                kind: .resumeRequest,
                matchID: matchID,
                stateVersion: latestGuestView.version
            )
        )
    }

    private func presentHostView() {
        guard let game else { return }
        let view = game.view(for: .playerOne)
        matchModel.update(
            from: view,
            claimableFlagIndices: claimableFlagIndices(in: game, for: .playerOne),
            localName: localPlayerName,
            opponentName: opponentName
        )
        matchModel.markConnected()
        persistSession()
    }

    private func sendGuestSnapshot() async throws {
        guard let game, let matchID else { return }
        let view = game.view(for: .playerTwo)
        let payload = StateSnapshotPayload(
            recipientSeat: Self.seatNumber(for: .playerTwo),
            encodedPlayerView: try MatchWireCoding.encoder.encode(view),
            claimableFlagIndices: claimableFlagIndices(in: game, for: .playerTwo)
        )
        try await send(
            .carrying(
                payload,
                kind: .stateSnapshot,
                matchID: matchID,
                stateVersion: view.version
            )
        )
    }

    private func claimableFlagIndices(
        in game: BattleLineGame,
        for player: PlayerID
    ) -> [Int] {
        guard game.currentPlayer == player,
              game.phase == .claimingAtTurnStart || game.phase == .claimingAfterPlay
        else { return [] }

        return FlagID.all.compactMap { flag in
            game.evaluateClaim(on: flag, by: player).isClaimable ? flag.rawValue : nil
        }
    }

    private func sendInTask(_ envelope: MatchWireEnvelope?) {
        guard let envelope else {
            statusMessage = "无法创建附近对局消息"
            matchModel.isSubmitting = false
            return
        }
        Task { [weak self] in
            do {
                try await self?.send(envelope)
            } catch {
                self?.handleSendFailure(error)
            }
        }
    }

    private func send(_ envelope: MatchWireEnvelope) async throws {
        guard let transport else { throw NearbyTransportError.notStarted }
        try await transport.send(MatchWireCoding.encode(envelope))
    }

    private func handleSendFailure(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        statusMessage = message
        matchModel.showError(message)
    }

    private func finishBecauseOpponentResigned() {
        sessionTerminated = true
        matchModel.phase = .finished(winner: .player)
        matchModel.notice = "对手已认输，本局结束"
        persistence.clear()
    }

    private func persistSession() {
        guard let role,
              let matchID,
              let resumeToken,
              let localSeat
        else { return }

        let persisted = PersistedNearbyMatch(
            role: role,
            matchID: matchID,
            resumeToken: resumeToken,
            localSeat: localSeat,
            localPlayerName: localPlayerName,
            opponentName: opponentName,
            pairingCode: pairingCode,
            advancedClaiming: advancedClaiming,
            game: role == .host ? game : nil,
            guestView: role == .guest ? latestGuestView : nil,
            guestClaimableFlagIndices: role == .guest ? latestGuestClaimableFlagIndices : [],
            processedCommandIDs: processedCommandIDs.sorted {
                $0.uuidString < $1.uuidString
            }
        )

        do {
            try persistence.save(persisted)
        } catch {
            statusMessage = "无法在本机保存当前对局"
        }
    }

    private func restorePersistedSession() {
        guard let persisted = persistence.load() else { return }

        switch persisted.role {
        case .host:
            guard persisted.localSeat == .playerOne,
                  let restoredGame = persisted.game
            else {
                persistence.clear()
                return
            }
            game = restoredGame
            latestGuestView = nil
            latestGuestClaimableFlagIndices = []
            hostSetup = MatchSetupDraft(
                playerName: persisted.localPlayerName,
                advancedClaiming: restoredGame.configuration.claimingRule == .advancedClaiming
            )

        case .guest:
            guard persisted.localSeat == .playerTwo,
                  let restoredView = persisted.guestView,
                  restoredView.viewer == .playerTwo
            else {
                persistence.clear()
                return
            }
            game = nil
            latestGuestView = restoredView
            latestGuestClaimableFlagIndices = persisted.guestClaimableFlagIndices
            hostSetup = nil
        }

        role = persisted.role
        matchID = persisted.matchID
        resumeToken = persisted.resumeToken
        localSeat = persisted.localSeat
        localPlayerName = persisted.localPlayerName
        opponentName = persisted.opponentName
        pairingCode = persisted.pairingCode
        advancedClaiming = persisted.advancedClaiming
        processedCommandIDs = Set(persisted.processedCommandIDs)
        sessionTerminated = false
        stage = .idle
        statusMessage = nil

        if let game {
            let view = game.view(for: .playerOne)
            matchModel.update(
                from: view,
                claimableFlagIndices: claimableFlagIndices(in: game, for: .playerOne),
                localName: localPlayerName,
                opponentName: opponentName
            )
        } else if let latestGuestView {
            matchModel.update(
                from: latestGuestView,
                claimableFlagIndices: latestGuestClaimableFlagIndices,
                localName: localPlayerName,
                opponentName: opponentName
            )
        }
        matchModel.markPaused("已从本机恢复对局，可继续连接")
    }

    private static func makePairingCode() -> String {
        let value = Int.random(in: 0 ..< 1_000_000)
        return String(format: "%03d %03d", value / 1_000, value % 1_000)
    }

    private static func normalizedPlayerName(_ name: String, fallback: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : String(trimmed.prefix(20))
    }

    private static func seatNumber(for player: PlayerID) -> Int {
        player == .playerOne ? 1 : 2
    }

    private static func playerID(for seat: Int) -> PlayerID? {
        switch seat {
        case 1: .playerOne
        case 2: .playerTwo
        default: nil
        }
    }

    private static func bluetoothExplanation(_ reason: NearbyBluetoothUnavailableReason) -> String {
        switch reason {
        case .poweredOff:
            "请在控制中心或系统设置中打开蓝牙；飞行模式下也需要手动重新打开蓝牙。"
        case .unauthorized:
            "请在系统设置中允许 BattleLine 使用蓝牙。"
        case .unsupported:
            "这台设备不支持所需的低功耗蓝牙功能。"
        case .resetting:
            "系统正在重置蓝牙，请稍后重试。"
        case .unknown:
            "蓝牙暂时不可用，请稍后重试。"
        }
    }

    private static func ruleErrorMessage(_ error: Error) -> String {
        guard let ruleError = error as? GameRuleError else {
            return "这次操作没有成功，请重试"
        }
        return switch ruleError {
        case .staleVersion:
            "对局状态已经更新，请按最新棋盘重试"
        case .gameAlreadyOver:
            "这局对战已经结束"
        case .notPlayersTurn:
            "现在不是你的回合"
        case .actionNotAllowed:
            "当前阶段不能执行这项操作"
        case .duplicateClaim:
            "同一面旗不能重复宣告"
        case .flagAlreadyClaimed:
            "这面旗已经被占领"
        case .flagNotClaimable:
            "公开信息还不足以证明你赢得这面旗"
        case .cardNotInHand:
            "这张牌已经不在你的手牌中"
        case .formationFull:
            "这条战线已经放满三张牌"
        case .cannotPlayOnClaimedFlag:
            "已占领的战线不能继续放牌"
        case .passWhileLegalMoveExists:
            "仍有合法位置时不能跳过出牌"
        }
    }
}

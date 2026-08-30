import BattleLineCore
import Foundation
import Testing
@testable import BattleLine

@Suite("Nearby match coordinator", .serialized)
@MainActor
struct NearbyMatchCoordinatorTests {
    @Test("Host hello discovery, approval, and initial snapshots stay recipient-scoped")
    func discoveryApprovalAndInitialSnapshots() async throws {
        let harness = makeHarness()
        defer { harness.stop() }

        harness.host.startHosting(
            setup: MatchSetupDraft(playerName: "房主甲", advancedClaiming: true)
        )
        harness.guest.startJoining(playerName: "加入者乙")

        try await waitUntil("guest discovers the advertised room") {
            harness.guest.stage == .roomFound
        }

        let room = try #require(harness.guest.discoveredRoom)
        #expect(room.hostName == "房主甲")
        #expect(room.pairingCode == harness.host.pairingCode)
        #expect(room.advancedClaiming)

        let helloEnvelope = try #require(
            harness.link.envelopes(sentBy: .host, kind: .hostHello).first
        )
        let hello = try helloEnvelope.decodePayload(HostHelloPayload.self)
        #expect(hello.hostName == "房主甲")
        #expect(hello.pairingCode == room.pairingCode)
        #expect(hello.advancedClaiming)

        harness.guest.requestToJoinDiscoveredRoom()

        try await waitUntil("host receives the join request") {
            harness.host.stage == .awaitingHostApproval
        }
        #expect(harness.host.pendingGuestName == "加入者乙")
        #expect(harness.guest.stage == .awaitingHostDecision)

        let requestEnvelope = try #require(
            harness.link.envelopes(sentBy: .join, kind: .joinRequest).first
        )
        let request = try requestEnvelope.decodePayload(JoinRequestPayload.self)
        #expect(request.playerName == "加入者乙")
        #expect(request.pairingCode == room.pairingCode)

        harness.host.approvePendingGuest()

        try await waitUntil("both peers receive their initial match views") {
            harness.host.stage == .active
                && harness.guest.stage == .active
                && harness.hostModel.hand.count == 7
                && harness.guestModel.hand.count == 7
        }

        #expect(harness.hostModel.opponentHandCount == 7)
        #expect(harness.guestModel.opponentHandCount == 7)
        #expect(harness.hostModel.deckCount == 46)
        #expect(harness.guestModel.deckCount == 46)
        #expect(Set(harness.hostModel.hand).isDisjoint(with: Set(harness.guestModel.hand)))
        #expect(harness.hostModel.lines.allSatisfy {
            $0.playerCards.isEmpty && $0.opponentCards.isEmpty
        })
        #expect(harness.guestModel.lines.allSatisfy {
            $0.playerCards.isEmpty && $0.opponentCards.isEmpty
        })

        let snapshotEnvelope = try #require(
            harness.link.envelopes(sentBy: .host, kind: .stateSnapshot).first
        )
        let snapshot = try snapshotEnvelope.decodePayload(StateSnapshotPayload.self)
        let guestView = try MatchWireCoding.decoder.decode(
            PlayerView.self,
            from: snapshot.encodedPlayerView
        )

        #expect(snapshot.recipientSeat == 2)
        #expect(guestView.viewer == .playerTwo)
        #expect(guestView.hand.count == 7)
        #expect(guestView.opponent.player == .playerOne)
        #expect(guestView.opponent.handCount == 7)
        #expect(Set(cardIDs(in: guestView.hand)) == Set(harness.guestModel.hand.map(\.id)))
        #expect(Set(cardIDs(in: guestView.hand)).isDisjoint(
            with: Set(harness.hostModel.hand.map(\.id))
        ))

        let viewJSON = try #require(
            JSONSerialization.jsonObject(with: snapshot.encodedPlayerView) as? [String: Any]
        )
        let opponentJSON = try #require(viewJSON["opponent"] as? [String: Any])
        #expect(Set(opponentJSON.keys) == ["handCount", "player"])
        #expect(viewJSON["deck"] == nil)
        #expect(viewJSON["playerOneHand"] == nil)
        #expect(viewJSON["playerTwoHand"] == nil)
    }

    @Test("A legal play is applied by the host and synchronized to both peers")
    func legalPlaySynchronizesAcrossPeers() async throws {
        let harness = makeHarness()
        defer { harness.stop() }

        harness.host.startHosting(
            setup: MatchSetupDraft(playerName: "房主", advancedClaiming: false)
        )
        harness.guest.startJoining(playerName: "加入者")

        try await waitUntil("guest discovers the room") {
            harness.guest.stage == .roomFound
        }
        harness.guest.requestToJoinDiscoveredRoom()
        try await waitUntil("host can approve the guest") {
            harness.host.stage == .awaitingHostApproval
        }
        harness.host.approvePendingGuest()
        try await waitUntil("both peers enter the match") {
            harness.host.stage == .active
                && harness.guest.stage == .active
                && harness.hostModel.hand.count == 7
                && harness.guestModel.hand.count == 7
        }

        let activeModel: MatchViewModel
        let observingModel: MatchViewModel
        if harness.hostModel.phase == .playCard {
            activeModel = harness.hostModel
            observingModel = harness.guestModel
        } else {
            activeModel = harness.guestModel
            observingModel = harness.hostModel
        }

        #expect(activeModel.phase == .playCard)
        #expect(observingModel.phase == .waitingForOpponentTurn)

        let playedCard = try #require(activeModel.hand.first)
        let targetLine = activeModel.lines[0]
        activeModel.selectCard(playedCard)
        activeModel.selectLine(targetLine)
        activeModel.confirmPlay()

        try await waitUntil("the authoritative move reaches both views") {
            harness.hostModel.stateVersion == 1
                && harness.guestModel.stateVersion == 1
                && activeModel.lines[0].playerCards == [playedCard]
                && observingModel.lines[0].opponentCards == [playedCard]
        }

        #expect(activeModel.hand.count == 6)
        #expect(!activeModel.hand.contains(playedCard))
        #expect(activeModel.phase == .claiming)
        #expect(observingModel.phase == .waitingForOpponentTurn)
        #expect(harness.hostModel.deckCount == 46)
        #expect(harness.guestModel.deckCount == 46)

        let actionCommands = harness.link.envelopes(sentBy: .join, kind: .actionCommand)
        if activeModel === harness.guestModel {
            #expect(actionCommands.count == 1)
        } else {
            #expect(actionCommands.isEmpty)
        }
        #expect(
            harness.link.envelopes(sentBy: .host, kind: .stateSnapshot).contains {
                $0.stateVersion == 1
            }
        )
    }

    @Test("Reconnect restores both match phases after either or both players leave",
          arguments: ["host", "guest", "both"])
    func reconnectRestoresMatchPhases(leaving: String) async throws {
        let harness = makeHarness()
        defer { harness.stop() }

        harness.host.startHosting(
            setup: MatchSetupDraft(playerName: "房主", advancedClaiming: false)
        )
        harness.guest.startJoining(playerName: "加入者")
        try await waitUntil("guest discovers the room") {
            harness.guest.stage == .roomFound
        }
        harness.guest.requestToJoinDiscoveredRoom()
        try await waitUntil("host can approve the guest") {
            harness.host.stage == .awaitingHostApproval
        }
        harness.host.approvePendingGuest()
        try await waitUntil("both peers enter the match") {
            harness.host.stage == .active && harness.guest.stage == .active
        }

        let hostPhase = harness.hostModel.phase
        let guestPhase = harness.guestModel.phase
        let hostHand = harness.hostModel.hand
        let guestHand = harness.guestModel.hand
        let version = harness.hostModel.stateVersion
        let snapshotsBefore = harness.link.envelopes(sentBy: .host, kind: .stateSnapshot).count

        if leaving != "guest" { harness.host.pauseAndReturnHome() }
        if leaving != "host" { harness.guest.pauseAndReturnHome() }
        try await waitUntil("both peers pause after disconnection") {
            if case .paused = harness.hostModel.phase,
               case .paused = harness.guestModel.phase { return true }
            return false
        }

        if leaving != "guest" { harness.host.resumeCurrentSession() }
        if leaving != "host" { harness.guest.resumeCurrentSession() }
        try await waitUntil("the resume handshake and snapshot complete") {
            harness.host.stage == .active && harness.guest.stage == .active
                && harness.link.envelopes(sentBy: .host, kind: .stateSnapshot).count > snapshotsBefore
        }

        #expect(harness.hostModel.phase == hostPhase)
        #expect(harness.guestModel.phase == guestPhase)
        #expect(harness.hostModel.connectionText == "纯蓝牙已连接")
        #expect(harness.guestModel.connectionText == "纯蓝牙已连接")
        #expect(harness.hostModel.hand == hostHand)
        #expect(harness.guestModel.hand == guestHand)
        #expect(harness.hostModel.stateVersion == version)
        #expect(harness.guestModel.stateVersion == version)
    }

    private func makeHarness() -> NearbyMatchHarness {
        let link = FakeNearbyLink()
        let hostModel = MatchViewModel()
        let guestModel = MatchViewModel()
        let persistenceDirectory = FileManager.default.temporaryDirectory
            .appending(path: "BattleLineCoordinatorTests-\(UUID().uuidString)")
        let host = NearbyMatchCoordinator(
            matchModel: hostModel,
            transportFactory: { role in link.makeTransport(role: role) },
            persistence: NearbyMatchPersistence(
                fileURL: persistenceDirectory.appending(path: "host.json")
            )
        )
        let guest = NearbyMatchCoordinator(
            matchModel: guestModel,
            transportFactory: { role in link.makeTransport(role: role) },
            persistence: NearbyMatchPersistence(
                fileURL: persistenceDirectory.appending(path: "guest.json")
            )
        )
        return NearbyMatchHarness(
            link: link,
            host: host,
            guest: guest,
            hostModel: hostModel,
            guestModel: guestModel
        )
    }

    private func cardIDs(in cards: [TroopCard]) -> [String] {
        cards.map { "\($0.color.rawValue)-\($0.value)" }
    }

    private func waitUntil(
        _ description: String,
        timeout: Duration = .seconds(2),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        if !condition() {
            Issue.record("Timed out waiting for \(description)")
            throw NearbyMatchTestError.timedOut(description)
        }
    }
}

@MainActor
private struct NearbyMatchHarness {
    let link: FakeNearbyLink
    let host: NearbyMatchCoordinator
    let guest: NearbyMatchCoordinator
    let hostModel: MatchViewModel
    let guestModel: MatchViewModel

    func stop() {
        host.abandonCurrentSession()
        guest.abandonCurrentSession()
    }
}

private enum NearbyMatchTestError: Error {
    case timedOut(String)
}

@MainActor
private final class FakeNearbyLink {
    struct Transmission {
        let sender: BLENearbyRole
        let payload: Data
    }

    private var host: FakeNearbyTransport?
    private var guest: FakeNearbyTransport?
    private(set) var transmissions: [Transmission] = []

    func makeTransport(role: BLENearbyRole) -> any NearbyTransport {
        let transport = FakeNearbyTransport(role: role, link: self)
        switch role {
        case .host:
            host = transport
        case .join:
            guest = transport
        }
        return transport
    }

    func start(_ transport: FakeNearbyTransport) {
        transport.setStarted(true)
        switch transport.role {
        case .host:
            transport.emit(.stateChanged(.advertising))
        case .join:
            transport.emit(.stateChanged(.scanning))
        }
        connectIfReady()
    }

    func stop(_ transport: FakeNearbyTransport) {
        guard transport.isStarted else { return }
        transport.setStarted(false)
        transport.emit(.stateChanged(.stopped))
        switch transport.role {
        case .host:
            if let guest, guest.isStarted {
                guest.emit(.stateChanged(.scanning))
            }
        case .join:
            if let host, host.isStarted {
                host.emit(.stateChanged(.advertising))
            }
        }
    }

    func send(_ payload: Data, from sender: FakeNearbyTransport) throws {
        let recipient: FakeNearbyTransport?
        switch sender.role {
        case .host:
            recipient = guest
        case .join:
            recipient = host
        }
        guard sender.isStarted, let recipient, recipient.isStarted else {
            throw NearbyTransportError.notConnected
        }

        transmissions.append(Transmission(sender: sender.role, payload: payload))
        recipient.emit(.received(payload))
    }

    func envelopes(sentBy sender: BLENearbyRole, kind: MatchWireKind) -> [MatchWireEnvelope] {
        transmissions.compactMap { transmission in
            guard transmission.sender == sender,
                  let envelope = try? MatchWireCoding.decode(transmission.payload),
                  envelope.kind == kind
            else { return nil }
            return envelope
        }
    }

    private func connectIfReady() {
        guard let host, host.isStarted, let guest, guest.isStarted else { return }
        host.emit(.stateChanged(.connected(peerID: "fake-guest")))
        guest.emit(.stateChanged(.connected(peerID: "fake-host")))
    }
}

@MainActor
private final class FakeNearbyTransport: NearbyTransport {
    let role: BLENearbyRole
    private(set) var state: NearbyConnectionState = .idle
    let events: AsyncStream<NearbyTransportEvent>

    private let continuation: AsyncStream<NearbyTransportEvent>.Continuation
    private weak var link: FakeNearbyLink?
    private(set) var isStarted = false

    init(role: BLENearbyRole, link: FakeNearbyLink) {
        self.role = role
        self.link = link
        let stream = AsyncStream<NearbyTransportEvent>.makeStream(bufferingPolicy: .unbounded)
        events = stream.stream
        continuation = stream.continuation
    }

    func start() {
        link?.start(self)
    }

    func stop() {
        link?.stop(self)
    }

    func send(_ payload: Data) async throws {
        guard let link else { throw NearbyTransportError.notStarted }
        try link.send(payload, from: self)
    }

    func setStarted(_ started: Bool) {
        isStarted = started
    }

    func emit(_ event: NearbyTransportEvent) {
        if case let .stateChanged(newState) = event {
            state = newState
        }
        continuation.yield(event)
    }
}

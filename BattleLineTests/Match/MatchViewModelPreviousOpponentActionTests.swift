import BattleLineCore
import Foundation
import Testing
@testable import BattleLine

@Suite("对手上一回合行动")
@MainActor
struct MatchViewModelPreviousOpponentActionTests {
    @Test("标准规则在对手完成宣称窗口后显示其出牌")
    func standardRuleShowsPlayAfterTurnChanges() throws {
        let viewer = PlayerID.playerOne
        var game = BattleLineGame(
            configuration: .init(claimingRule: .standard),
            dealer: viewer,
            seed: 101
        )
        let actor = viewer.opponent
        let card = try #require(game.hand(for: actor).first)
        let flag = FlagID(rawValue: 4)
        let model = MatchViewModel()

        try game.apply(.init(
            actor: actor,
            expectedVersion: game.version,
            action: .play(card: card, to: flag)
        ))
        update(model, from: game.view(for: viewer))
        #expect(model.phase == .waitingForOpponentTurn)
        #expect(model.previousOpponentAction == nil)

        try game.apply(.init(
            actor: actor,
            expectedVersion: game.version,
            action: .declareClaims([])
        ))
        update(model, from: game.view(for: viewer))

        let expected = PreviousOpponentActionPresentation.played(
            card: TroopCardPresentation(
                color: presentationColor(card.color),
                value: card.value
            ),
            lineID: flag.rawValue
        )
        #expect(model.phase == .playCard)
        #expect(model.previousOpponentAction == expected)

        let viewerCard = try #require(game.hand(for: viewer).first)
        try game.apply(.init(
            actor: viewer,
            expectedVersion: game.version,
            action: .play(card: viewerCard, to: FlagID(rawValue: 0))
        ))
        update(model, from: game.view(for: viewer))
        #expect(model.phase == .claiming)
        #expect(model.previousOpponentAction == expected)
    }

    @Test("高级规则在我方宣称与出牌阶段都保留对手上一手")
    func advancedRuleKeepsPlayAcrossLocalPhases() throws {
        let viewer = PlayerID.playerTwo
        var game = BattleLineGame(
            configuration: .init(claimingRule: .advancedClaiming),
            dealer: viewer,
            seed: 202
        )
        let actor = viewer.opponent
        let card = try #require(game.hand(for: actor).first)
        let flag = FlagID(rawValue: 6)
        let expected = PreviousOpponentActionPresentation.played(
            card: TroopCardPresentation(
                color: presentationColor(card.color),
                value: card.value
            ),
            lineID: flag.rawValue
        )

        try game.apply(.init(
            actor: actor,
            expectedVersion: game.version,
            action: .declareClaims([])
        ))
        try game.apply(.init(
            actor: actor,
            expectedVersion: game.version,
            action: .play(card: card, to: flag)
        ))

        let model = MatchViewModel()
        update(model, from: game.view(for: viewer))
        #expect(model.phase == .claiming)
        #expect(model.previousOpponentAction == expected)

        try game.apply(.init(
            actor: viewer,
            expectedVersion: game.version,
            action: .declareClaims([])
        ))
        update(model, from: game.view(for: viewer))
        #expect(model.phase == .playCard)
        #expect(model.previousOpponentAction == expected)
    }

    @Test("对手上一回合跳过时不回退显示更早的出牌")
    func passDoesNotFallBackToAnOlderPlay() throws {
        let viewer = PlayerID.playerOne
        let oldCard = try TroopCard(color: .red, value: 2)
        let log = [
            GameLogEntry(
                version: 1,
                turn: 1,
                actor: viewer.opponent,
                action: .play(card: oldCard, to: FlagID(rawValue: 1)),
                events: []
            ),
            GameLogEntry(
                version: 2,
                turn: 3,
                actor: viewer.opponent,
                action: .pass,
                events: [.passed(player: viewer.opponent)]
            ),
        ]
        let view = try makeView(
            viewer: viewer,
            currentPlayer: viewer,
            phase: .playing,
            turn: 4,
            version: 2,
            log: log
        )

        let model = MatchViewModel()
        update(model, from: view)

        #expect(model.previousOpponentAction == .passed)
    }

    @Test("首回合、对手回合和终局都不派生上一手")
    func unavailableTurnsDoNotExposeAnAction() throws {
        let viewer = PlayerID.playerOne
        let model = MatchViewModel()
        var game = BattleLineGame(dealer: viewer.opponent, seed: 303)

        update(model, from: game.view(for: viewer))
        #expect(model.phase == .playCard)
        #expect(model.previousOpponentAction == nil)

        let card = try #require(game.hand(for: viewer).first)
        try game.apply(.init(
            actor: viewer,
            expectedVersion: game.version,
            action: .play(card: card, to: FlagID(rawValue: 0))
        ))
        try game.apply(.init(
            actor: viewer,
            expectedVersion: game.version,
            action: .declareClaims([])
        ))
        update(model, from: game.view(for: viewer))
        #expect(model.phase == .waitingForOpponentTurn)
        #expect(model.previousOpponentAction == nil)

        let opponent = viewer.opponent
        let opponentCard = try #require(game.hand(for: opponent).first)
        try game.apply(.init(
            actor: opponent,
            expectedVersion: game.version,
            action: .play(card: opponentCard, to: FlagID(rawValue: 1))
        ))
        try game.apply(.init(
            actor: opponent,
            expectedVersion: game.version,
            action: .declareClaims([])
        ))
        let finishedView = try replacingWinner(
            in: game.view(for: viewer),
            with: opponent
        )
        update(model, from: finishedView)
        #expect(model.phase == .finished(winner: .opponent))
        #expect(model.previousOpponentAction == nil)
    }

    @Test("新对局重置会清空上一手，预览显示橙9到战线5")
    func resetAndPreviewState() {
        let model = MatchViewModel.preview()
        let orangeNine = TroopCardPresentation(color: .orange, value: 9)
        #expect(model.turn == 2)
        #expect(model.previousOpponentAction == .played(card: orangeNine, lineID: 4))
        #expect(model.lines[4].opponentCards.contains(orangeNine))

        model.prepareForHost(name: "玩家", code: "123 456")
        #expect(model.previousOpponentAction == nil)
    }

    private func update(_ model: MatchViewModel, from view: PlayerView) {
        model.update(
            from: view,
            claimableFlagIndices: [],
            localName: "我方",
            opponentName: "对手"
        )
    }

    private func makeView(
        viewer: PlayerID,
        currentPlayer: PlayerID,
        phase: TurnPhase,
        turn: UInt64,
        version: UInt64,
        log: [GameLogEntry]
    ) throws -> PlayerView {
        let base = BattleLineGame(dealer: viewer.opponent, seed: 404).view(for: viewer)
        var object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(base)) as? [String: Any]
        )
        object["currentPlayer"] = currentPlayer.rawValue
        object["phase"] = phase.rawValue
        object["turn"] = turn
        object["version"] = version
        object["log"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(log))
        return try JSONDecoder().decode(
            PlayerView.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
    }

    private func replacingWinner(
        in view: PlayerView,
        with winner: PlayerID
    ) throws -> PlayerView {
        var object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(view)) as? [String: Any]
        )
        object["winner"] = winner.rawValue
        return try JSONDecoder().decode(
            PlayerView.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
    }

    private func presentationColor(_ color: TroopColor) -> TroopColorPresentation {
        switch color {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .blue: .blue
        case .purple: .purple
        }
    }
}

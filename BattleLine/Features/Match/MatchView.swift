import SwiftUI

struct MatchView: View {
    @Bindable var model: MatchViewModel
    let leaveMatch: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            MatchTopBar(model: model, leaveMatch: leaveMatch)

            HStack(spacing: 9) {
                VStack(spacing: 7) {
                    battlefield
                    HandView(model: model)
                }
                .frame(maxWidth: .infinity)

                MatchCommandView(model: model, leaveMatch: leaveMatch)
                    .frame(width: 180)
            }
            .padding(.leading, 9)
            .padding(.trailing, 16)
            .padding(.vertical, 9)
            .ignoresSafeArea(.container, edges: .trailing)
        }
    }

    private var battlefield: some View {
        HStack(spacing: 6) {
            Button {
                model.moveWindow(-3)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 40)
                    .frame(maxHeight: .infinity)
            }
            .buttonStyle(BattleWindowButtonStyle())
            .disabled(!model.canMoveLeft)
            .accessibilityLabel("显示左侧三条战线")

            HStack(spacing: 7) {
                ForEach(model.visibleLines) { line in
                    FlagLineView(
                        line: line,
                        selectedForPlay: model.selectedLineID == line.id,
                        selectedForClaim: model.selectedClaimIDs.contains(line.id),
                        interactive: isLineInteractive(line),
                        select: {
                            if model.phase == .claiming {
                                model.toggleClaim(line)
                            } else {
                                model.selectLine(line)
                            }
                        }
                    )
                }
            }
            .frame(maxWidth: .infinity)

            Button {
                model.moveWindow(3)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 40)
                    .frame(maxHeight: .infinity)
            }
            .buttonStyle(BattleWindowButtonStyle())
            .disabled(!model.canMoveRight)
            .accessibilityLabel("显示右侧三条战线")
        }
        .frame(maxHeight: .infinity)
    }

    private func isLineInteractive(_ line: BattleLinePresentation) -> Bool {
        if model.isSubmitting { return false }
        return switch model.phase {
        case .claiming:
            line.isClaimable
        case .playCard:
            line.owner == nil && line.playerCards.count < 3
        default:
            false
        }
    }
}

private struct MatchTopBar: View {
    let model: MatchViewModel
    let leaveMatch: () -> Void

    var body: some View {
        HStack(spacing: 11) {
            Text("BattleLine")
                .font(.headline)

            Label("第 \(model.turn) 回合", systemImage: "arrow.triangle.2.circlepath")
                .font(.subheadline)
                .foregroundStyle(BattleLineTheme.mutedInk)

            Spacer()

            Label("\(model.opponentName) · \(model.opponentHandCount) 张", systemImage: "person.crop.circle")
                .foregroundStyle(BattleLineTheme.mutedInk)

            Label("牌堆 \(model.deckCount)", systemImage: "rectangle.stack")
                .foregroundStyle(BattleLineTheme.mutedInk)

            HStack(spacing: 6) {
                Circle()
                    .fill(connectionColor)
                    .frame(width: 8, height: 8)
                Text(model.connectionText)
            }
            .foregroundStyle(BattleLineTheme.mutedInk)

            Button("返回首页", action: leaveMatch)
                .buttonStyle(.borderless)
        }
        .font(.subheadline)
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background(BattleLineTheme.surface.opacity(0.86))
    }

    private var connectionColor: Color {
        if case .paused = model.phase { return .orange }
        return model.connectionText.contains("已连接") ? .green : BattleLineTheme.gold
    }
}

private struct FlagLineView: View {
    let line: BattleLinePresentation
    let selectedForPlay: Bool
    let selectedForClaim: Bool
    let interactive: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(spacing: 4) {
                FormationView(cards: line.opponentCards)
                    .rotationEffect(.degrees(180))

                HStack(spacing: 5) {
                    Text((line.id + 1).formatted())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BattleLineTheme.mutedInk)
                    FlagMarker(
                        owner: line.owner,
                        isClaimable: line.isClaimable,
                        isSelected: selectedForClaim
                    )
                }

                FormationView(cards: line.playerCards)
            }
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .battlePanel(selected: selectedForPlay || selectedForClaim)
        .disabled(!interactive)
        .opacity(line.owner == nil ? 1 : 0.78)
        .accessibilityLabel("战线 \(line.id + 1)")
        .accessibilityValue(flagAccessibilityValue)
    }

    private var flagAccessibilityValue: String {
        switch line.owner {
        case .player: "你已占领"
        case .opponent: "对方已占领"
        case nil where line.isClaimable: "现在可以宣告占领"
        case nil: "未占领"
        }
    }
}

private struct FormationView: View {
    let cards: [TroopCardPresentation]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(cards) { card in
                TroopCardView(card: card, compact: true)
            }
            ForEach(cards.count ..< 3, id: \.self) { _ in
                EmptyTroopSlotView()
            }
        }
    }
}

private struct FlagMarker: View {
    let owner: FlagOwnerPresentation?
    let isClaimable: Bool
    let isSelected: Bool

    var body: some View {
        Image(systemName: owner == nil ? "mappin" : "flag.fill")
            .font(.title2)
            .foregroundStyle(markerColor)
            .frame(width: 30, height: 32)
            .background {
                if isClaimable {
                    Circle()
                        .stroke(BattleLineTheme.gold, lineWidth: isSelected ? 3 : 1.5)
                        .padding(1)
                }
            }
    }

    private var markerColor: Color {
        switch owner {
        case .player: BattleLineTheme.gold
        case .opponent: BattleLineTheme.mutedInk
        case nil: BattleLineTheme.flag
        }
    }
}

private struct HandView: View {
    @Bindable var model: MatchViewModel

    var body: some View {
        HStack(spacing: 9) {
            VStack(alignment: .leading, spacing: 2) {
                Text("你的手牌")
                    .font(.headline)
                Text(handHint)
                    .font(.caption)
                    .foregroundStyle(BattleLineTheme.mutedInk)
            }
            .fixedSize()

            if model.hand.isEmpty {
                Text("没有手牌")
                    .font(.caption)
                    .foregroundStyle(BattleLineTheme.mutedInk)
                    .frame(maxWidth: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(model.hand) { card in
                            Button {
                                model.selectCard(card)
                            } label: {
                                TroopCardView(
                                    card: card,
                                    selected: model.selectedCardID == card.id
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(model.phase != .playCard || model.isSubmitting)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .frame(height: 78)
        .battlePanel()
    }

    private var handHint: String {
        switch model.phase {
        case .playCard: "先选牌，再选战线"
        case .claiming: "先完成占旗阶段"
        case .waitingForOpponentTurn: "等待对手"
        case .paused: "连接恢复后继续"
        default: ""
        }
    }
}

private struct MatchCommandView: View {
    @Bindable var model: MatchViewModel
    let leaveMatch: () -> Void

    private let claimColumns = [
        GridItem(.flexible(), spacing: 5),
        GridItem(.flexible(), spacing: 5),
        GridItem(.flexible(), spacing: 5),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(phaseTitle)
                    .font(.headline)
                Spacer()
                if model.isSubmitting {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Circle()
                        .fill(phaseColor)
                        .frame(width: 8, height: 8)
                }
            }

            Divider()

            if model.phase == .claiming {
                claimControls
            } else if model.phase == .playCard {
                playControls
            } else {
                stateMessage
            }

            if let notice = model.notice {
                Label(notice, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if case .finished = model.phase {
                Button("返回首页", action: leaveMatch)
                    .buttonStyle(BattlePrimaryButtonStyle())
            }
        }
        .padding(11)
        .battlePanel()
    }

    private var claimControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("按宣告顺序选择旗帜，可多选")
                .font(.caption)
                .foregroundStyle(BattleLineTheme.mutedInk)

            if model.claimableLines.isEmpty {
                Text("当前没有可以证明获胜的旗帜")
                    .font(.caption)
                    .foregroundStyle(BattleLineTheme.mutedInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: claimColumns, spacing: 5) {
                        ForEach(model.claimableLines) { line in
                            Button {
                                model.toggleClaim(line)
                            } label: {
                                VStack(spacing: 0) {
                                    Text((line.id + 1).formatted())
                                        .font(.subheadline.monospacedDigit().weight(.bold))
                                    if let order = model.selectedClaimIDs.firstIndex(of: line.id) {
                                        Text("第 \(order + 1) 个")
                                            .font(.system(size: 8, weight: .semibold))
                                    }
                                }
                                    .frame(maxWidth: .infinity, minHeight: 34)
                                    .background(
                                        model.selectedClaimIDs.contains(line.id)
                                            ? BattleLineTheme.gold
                                            : BattleLineTheme.raisedSurface,
                                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    )
                                    .foregroundStyle(
                                        model.selectedClaimIDs.contains(line.id)
                                            ? BattleLineTheme.surface
                                            : BattleLineTheme.ink
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 82)
            }

            Button {
                model.confirmClaims()
            } label: {
                Text(claimButtonTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(BattlePrimaryButtonStyle())
            .disabled(model.isSubmitting)
        }
    }

    private var playControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let card = model.selectedCard {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(card.color.localizedName) \(card.value)")
                        .font(.headline)
                    Text(selectedTargetText)
                        .font(.caption)
                        .foregroundStyle(BattleLineTheme.mutedInk)
                }
                .padding(9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(BattleLineTheme.raisedSurface, in: BattleLineTheme.controlShape)
            } else {
                Text(model.hasLegalPlay ? "从手牌选一张兵种牌，再选择一条未满战线。" : "目前没有合法出牌位置，可以跳过出牌。")
                    .font(.caption)
                    .foregroundStyle(BattleLineTheme.mutedInk)
            }

            Button {
                if model.hasLegalPlay {
                    model.confirmPlay()
                } else {
                    model.pass()
                }
            } label: {
                Text(model.hasLegalPlay ? "确认出牌" : "跳过出牌")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(BattlePrimaryButtonStyle())
            .disabled(
                model.isSubmitting
                    || (model.hasLegalPlay
                        && (model.selectedCardID == nil || model.selectedLineID == nil))
            )
        }
    }

    private var stateMessage: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(commandHint)
                .foregroundStyle(BattleLineTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)

            if case .paused = model.phase {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var phaseTitle: String {
        switch model.phase {
        case .waitingForOpponent: "等待对手"
        case .claiming: "宣告占旗"
        case .playCard: "你的回合"
        case .waitingForOpponentTurn: "对手回合"
        case .paused: "对局暂停"
        case .finished: "对局结束"
        }
    }

    private var phaseColor: Color {
        switch model.phase {
        case .playCard, .claiming: BattleLineTheme.gold
        case .waitingForOpponentTurn, .waitingForOpponent: BattleLineTheme.mutedInk
        case .paused: .orange
        case .finished: .green
        }
    }

    private var selectedTargetText: String {
        guard let selectedLineID = model.selectedLineID else { return "请选择战线" }
        return "准备放到战线 \(selectedLineID + 1)"
    }

    private var claimButtonTitle: String {
        let count = model.selectedClaimIDs.count
        return count == 0 ? "本阶段不占旗" : "确认占领 \(count) 面旗"
    }

    private var commandHint: String {
        switch model.phase {
        case .waitingForOpponent:
            "等待附近玩家完成配对"
        case .waitingForOpponentTurn:
            "等待 \(model.opponentName) 完成操作"
        case let .paused(reason):
            reason
        case let .finished(winner):
            winner == .player ? "你赢得了本局" : "\(model.opponentName) 赢得了本局"
        case .playCard, .claiming:
            ""
        }
    }
}

private struct BattleWindowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(BattleLineTheme.ink.opacity(configuration.isPressed ? 0.6 : 1))
            .background(
                BattleLineTheme.raisedSurface,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
    }
}

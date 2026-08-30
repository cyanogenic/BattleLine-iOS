import SwiftUI

struct JoinLobbyView: View {
    @Bindable var coordinator: NearbyMatchCoordinator
    let cancel: () -> Void

    var body: some View {
        HStack(spacing: 22) {
            VStack(alignment: .leading, spacing: 14) {
                Button(action: cancel) {
                    Label("返回", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)

                Spacer(minLength: 4)

                Text("加入附近对局")
                    .font(.largeTitle.bold())
                Text("BattleLine 会用纯蓝牙自动连接附近的房主，不需要互联网、Wi‑Fi 或个人热点。")
                    .foregroundStyle(BattleLineTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)

                Label("双方请保持 App 在前台", systemImage: "iphone.gen3")
                    .foregroundStyle(BattleLineTheme.gold)

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 14) {
                TextField("你的名称", text: $coordinator.localPlayerName)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.done)
                    .disabled(isJoinRequestSent)

                Divider()

                stageContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let statusMessage = coordinator.statusMessage {
                    Label(statusMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)
            .frame(maxWidth: 410, maxHeight: .infinity)
            .battlePanel()
        }
        .padding(24)
    }

    @ViewBuilder
    private var stageContent: some View {
        switch coordinator.stage {
        case .startingBluetooth, .scanning, .connecting:
            waitingView(
                title: coordinator.stage == .connecting ? "正在建立蓝牙连接" : "正在寻找 BattleLine 房间",
                detail: "首次使用时，请允许 BattleLine 访问蓝牙。"
            )

        case .roomFound:
            if let room = coordinator.discoveredRoom {
                roomView(room)
            } else {
                waitingView(title: "正在读取房间信息", detail: "请稍候。")
            }

        case .awaitingHostDecision, .awaitingSnapshot:
            VStack(spacing: 14) {
                Image(systemName: "person.badge.clock")
                    .font(.system(size: 34))
                    .foregroundStyle(BattleLineTheme.gold)
                Text("等待房主允许加入")
                    .font(.title3.bold())
                Text("请确认房主屏幕也显示配对码")
                    .foregroundStyle(BattleLineTheme.mutedInk)
                pairingCodeView(coordinator.pairingCode)
                ProgressView()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .reconnecting:
            waitingView(
                title: "正在恢复对局",
                detail: "找到原房主后会自动同步最新棋盘。"
            )

        case let .unavailable(explanation):
            unavailableView(title: "蓝牙不可用", explanation: explanation)

        case let .failed(message):
            unavailableView(title: "连接失败", explanation: message)

        case .idle:
            unavailableView(title: "扫描已停止", explanation: "返回后可以重新开始扫描。")

        case .advertising, .awaitingHostApproval:
            unavailableView(title: "角色状态异常", explanation: "请返回首页后重试。")

        case .active:
            waitingView(title: "正在进入对局", detail: "棋盘已经同步。")
        }
    }

    private func roomView(_ room: NearbyRoomPresentation) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(room.hostName, systemImage: "iphone.radiowaves.left.and.right")
                .font(.title3.bold())

            HStack {
                Text("配对码")
                    .foregroundStyle(BattleLineTheme.mutedInk)
                Spacer()
                pairingCodeView(room.pairingCode)
            }

            HStack {
                Text("占旗规则")
                    .foregroundStyle(BattleLineTheme.mutedInk)
                Spacer()
                Text(room.advancedClaiming ? "仅回合开始占旗" : "出牌后占旗")
                    .font(.subheadline.weight(.semibold))
            }

            Spacer(minLength: 0)

            Text("加入前，请与房主口头核对配对码。")
                .font(.caption)
                .foregroundStyle(BattleLineTheme.mutedInk)

            Button {
                coordinator.requestToJoinDiscoveredRoom()
            } label: {
                Label("请求加入", systemImage: "person.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(BattlePrimaryButtonStyle())
            .disabled(coordinator.localPlayerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func waitingView(title: String, detail: String) -> some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text(title)
                .font(.title3.bold())
            Text(detail)
                .multilineTextAlignment(.center)
                .foregroundStyle(BattleLineTheme.mutedInk)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func unavailableView(title: String, explanation: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "bluetooth.slash")
                .font(.system(size: 34))
                .foregroundStyle(.orange)
            Text(title)
                .font(.title3.bold())
            Text(explanation)
                .multilineTextAlignment(.center)
                .foregroundStyle(BattleLineTheme.mutedInk)
            Button("重试") {
                coordinator.retryBluetooth()
            }
            .buttonStyle(BattleSecondaryButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func pairingCodeView(_ code: String) -> some View {
        Text(code)
            .font(.title3.monospacedDigit().weight(.bold))
            .tracking(1.2)
            .foregroundStyle(BattleLineTheme.gold)
    }

    private var isJoinRequestSent: Bool {
        coordinator.stage == .awaitingHostDecision
            || coordinator.stage == .awaitingSnapshot
            || coordinator.stage == .reconnecting
            || coordinator.stage == .active
    }
}

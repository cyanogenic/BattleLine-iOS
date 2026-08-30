import SwiftUI

struct HostLobbyView: View {
    @Bindable var coordinator: NearbyMatchCoordinator
    let cancel: () -> Void

    var body: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 14) {
                Button(action: cancel) {
                    Label("取消房间", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)

                Spacer(minLength: 4)

                Text("等待附近玩家")
                    .font(.largeTitle.bold())
                Text("另一台 iPhone 选择你的房间后，你会在这里看到对方名称并决定是否允许加入。")
                    .foregroundStyle(BattleLineTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)

                Label("请让双方保持 App 在前台", systemImage: "iphone.gen3.radiowaves.left.and.right")
                    .foregroundStyle(BattleLineTheme.gold)

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 16) {
                Text("配对码")
                    .font(.headline)
                    .foregroundStyle(BattleLineTheme.mutedInk)
                Text(coordinator.pairingCode)
                    .font(.system(.largeTitle, design: .monospaced, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(BattleLineTheme.gold)

                Divider()

                stageContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let statusMessage = coordinator.statusMessage {
                    Label(statusMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding(22)
            .frame(maxWidth: 400, maxHeight: .infinity)
            .battlePanel()
        }
        .padding(26)
    }

    @ViewBuilder
    private var stageContent: some View {
        switch coordinator.stage {
        case .awaitingHostApproval:
            VStack(spacing: 12) {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.system(size: 38))
                    .foregroundStyle(BattleLineTheme.gold)
                Text(coordinator.pendingGuestName ?? "附近玩家")
                    .font(.title3.bold())
                Text("请求加入这局对战")
                    .foregroundStyle(BattleLineTheme.mutedInk)

                HStack(spacing: 10) {
                    Button("拒绝") {
                        coordinator.rejectPendingGuest()
                    }
                    .buttonStyle(BattleSecondaryButtonStyle())

                    Button("允许加入") {
                        coordinator.approvePendingGuest()
                    }
                    .buttonStyle(BattlePrimaryButtonStyle())
                }
            }

        case let .unavailable(explanation):
            failureView(title: "蓝牙不可用", message: explanation)

        case let .failed(message):
            failureView(title: "广播失败", message: message)

        case .active:
            ProgressView("正在进入对局")

        default:
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text(stageTitle)
                    .font(.title3.bold())
                Text("请让对方打开 BattleLine 并选择“加入附近对局”。")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(BattleLineTheme.mutedInk)
            }
        }
    }

    private func failureView(title: String, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "bluetooth.slash")
                .font(.system(size: 36))
                .foregroundStyle(.orange)
            Text(title)
                .font(.title3.bold())
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(BattleLineTheme.mutedInk)
            Button("重试") {
                coordinator.retryBluetooth()
            }
            .buttonStyle(BattleSecondaryButtonStyle())
        }
    }

    private var stageTitle: String {
        switch coordinator.stage {
        case .startingBluetooth:
            "正在启动蓝牙"
        case .connecting:
            "已发现玩家，正在建立连接"
        case .reconnecting:
            "等待对手重新连接"
        default:
            "正在广播房间"
        }
    }
}

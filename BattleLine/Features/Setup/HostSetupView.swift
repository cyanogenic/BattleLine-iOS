import SwiftUI

struct HostSetupView: View {
    @Binding var setup: MatchSetupDraft
    let cancel: () -> Void
    let create: () -> Void

    var body: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 14) {
                Button(action: cancel) {
                    Label("返回", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)

                Spacer(minLength: 8)

                Text("创建附近对局")
                    .font(.largeTitle.bold())
                Text("房主保存完整牌序并验证双方操作。另一台 iPhone 通过蓝牙加入。")
                    .foregroundStyle(BattleLineTheme.mutedInk)

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 18) {
                TextField("你的名称", text: $setup.playerName)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.done)

                Toggle(isOn: $setup.advancedClaiming) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("高级占旗")
                            .font(.headline)
                        Text("只能在回合开始时宣告占领旗帜")
                            .foregroundStyle(BattleLineTheme.mutedInk)
                    }
                }
                .tint(BattleLineTheme.gold)

                Divider()

                Label("60 张兵种牌 · 9 面旗帜", systemImage: "rectangle.stack")
                Label("三连旗或任意五旗获胜", systemImage: "flag.2.crossed")

                Spacer(minLength: 0)

                Button(action: create) {
                    Label("开始广播房间", systemImage: "antenna.radiowaves.left.and.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BattlePrimaryButtonStyle())
                .disabled(setup.playerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(22)
            .frame(maxWidth: 390, maxHeight: .infinity)
            .battlePanel()
        }
        .padding(26)
    }
}


import SwiftUI

struct SettingsView: View {
    let nickname: String
    @Bindable var feedbackSettings: FeedbackSettings
    let back: () -> Void
    let showPersonalInfo: () -> Void
    let setHapticsEnabled: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Button(action: back) {
                Label("返回", systemImage: "chevron.left")
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("设置")
                        .font(.largeTitle.bold())

                    Button(action: showPersonalInfo) {
                        HStack(spacing: 16) {
                            Image(systemName: "person.crop.circle")
                                .font(.title)
                                .foregroundStyle(BattleLineTheme.gold)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("个人信息")
                                    .font(.headline)
                                Text(nickname)
                                    .foregroundStyle(BattleLineTheme.mutedInk)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(BattleLineTheme.mutedInk)
                        }
                        .padding(22)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .battlePanel()
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.personalInfo")

                    VStack(alignment: .leading, spacing: 18) {
                        Label("音效与震动", systemImage: "speaker.wave.2")
                            .font(.headline)

                        Toggle("回合提示音", isOn: $feedbackSettings.soundEnabled)
                            .accessibilityIdentifier("settings.turnSound")
                        Toggle("回合震动", isOn: Binding(
                            get: { feedbackSettings.hapticsEnabled },
                            set: setHapticsEnabled
                        ))
                            .accessibilityIdentifier("settings.turnHaptics")

                        Text("对手结束回合时提醒，仅在前台对战中触发。开启震动开关可预览两次敲击效果。提示音遵循系统静音设置。")
                            .font(.footnote)
                            .foregroundStyle(BattleLineTheme.mutedInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .toggleStyle(.switch)
                    .tint(BattleLineTheme.gold)
                    .padding(22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .battlePanel()
                }
                .frame(maxWidth: 620, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 12)
            }
        }
        .padding(.horizontal, 26)
        .padding(.bottom, 20)
        .foregroundStyle(BattleLineTheme.ink)
    }
}

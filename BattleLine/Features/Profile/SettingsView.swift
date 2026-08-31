import SwiftUI

struct SettingsView: View {
    let nickname: String
    let back: () -> Void
    let showPersonalInfo: () -> Void

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

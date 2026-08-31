import SwiftUI

struct NicknameEditorView: View {
    let isFirstLaunch: Bool
    let cancel: (() -> Void)?
    let save: (String) -> Bool

    @State private var draft: String
    @State private var attemptedSave = false
    @FocusState private var isNicknameFocused: Bool

    init(
        isFirstLaunch: Bool,
        initialNickname: String,
        cancel: (() -> Void)? = nil,
        save: @escaping (String) -> Bool
    ) {
        self.isFirstLaunch = isFirstLaunch
        self.cancel = cancel
        self.save = save
        _draft = State(initialValue: initialNickname)
    }

    private var validationMessage: String? {
        NicknameRules.validationMessage(for: draft)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let cancel {
                HStack {
                    Button(action: cancel) {
                        Label("设置", systemImage: "chevron.left")
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.horizontal, 26)
            }

            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(isFirstLaunch ? "欢迎来到 BattleLine" : "个人信息")
                                .font(.largeTitle.bold())
                            Text(isFirstLaunch
                                 ? "先取一个昵称，让附近的对手认出你。"
                                 : "修改后的昵称仅用于新对局，未结束的对局保留原昵称。")
                                .foregroundStyle(BattleLineTheme.mutedInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            Text("昵称")
                                .font(.headline)
                            TextField("请输入昵称", text: $draft)
                                .textFieldStyle(.roundedBorder)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .submitLabel(.done)
                                .focused($isNicknameFocused)
                                .onSubmit(submit)
                                .accessibilityLabel("昵称")
                                .accessibilityIdentifier("profile.nickname")

                            HStack(alignment: .top) {
                                Text("支持空格和表情，首尾空格会自动去除。")
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 8)
                                Text("\(NicknameRules.normalized(draft).count)/\(NicknameRules.maximumCharacters)")
                                    .monospacedDigit()
                                    .fixedSize()
                            }
                            .font(.caption)
                            .foregroundStyle(BattleLineTheme.mutedInk)

                            if let validationMessage, !draft.isEmpty || attemptedSave {
                                Text(validationMessage)
                                    .font(.caption)
                                    .foregroundStyle(BattleLineTheme.flag)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Button(action: submit) {
                                Text(isFirstLaunch ? "开始游戏" : "保存昵称")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(BattlePrimaryButtonStyle())
                            .disabled(validationMessage != nil)
                            .opacity(validationMessage == nil ? 1 : 0.45)
                            .accessibilityIdentifier("profile.save")
                        }
                        .padding(22)
                        .battlePanel()

                        if isFirstLaunch {
                            Text("昵称保存在本机，之后可在「设置 → 个人信息」修改。")
                                .font(.caption)
                                .foregroundStyle(BattleLineTheme.mutedInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: 560)
                    .padding(24)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .foregroundStyle(BattleLineTheme.ink)
    }

    private func submit() {
        attemptedSave = true
        guard validationMessage == nil else { return }
        if save(draft) {
            isNicknameFocused = false
        }
    }
}

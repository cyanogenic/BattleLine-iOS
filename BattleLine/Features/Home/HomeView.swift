import SwiftUI

struct HomeView: View {
    let createMatch: () -> Void
    let joinMatch: () -> Void
    let hasResumableMatch: Bool
    let continueMatch: () -> Void
    let abandonMatch: () -> Void

    @State private var confirmingAbandonment = false

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 28) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("BattleLine")
                        .font(.system(.largeTitle, design: .serif, weight: .semibold))
                    Text("在附近的两台 iPhone 之间，用纯蓝牙展开九条战线的较量。")
                        .font(.title3)
                        .foregroundStyle(BattleLineTheme.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)
                    Label("无需互联网或个人热点", systemImage: "airplane")
                        .foregroundStyle(BattleLineTheme.gold)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 12) {
                    if hasResumableMatch {
                        Button(action: continueMatch) {
                            Label("继续附近对局", systemImage: "arrow.clockwise.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(BattlePrimaryButtonStyle())

                        Button(role: .destructive) {
                            confirmingAbandonment = true
                        } label: {
                            Label("结束当前对局", systemImage: "xmark.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(BattleSecondaryButtonStyle())

                        Divider()
                    }

                    Button(action: createMatch) {
                        Label("创建对局", systemImage: "antenna.radiowaves.left.and.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BattlePrimaryButtonStyle())
                    .disabled(hasResumableMatch)

                    Button(action: joinMatch) {
                        Label("加入附近对局", systemImage: "dot.radiowaves.left.and.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BattleSecondaryButtonStyle())
                    .disabled(hasResumableMatch)
                }
                .frame(width: min(320, proxy.size.width * 0.42))
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .confirmationDialog(
            "结束当前对局？",
            isPresented: $confirmingAbandonment,
            titleVisibility: .visible
        ) {
            Button("结束并清除", role: .destructive, action: abandonMatch)
            Button("取消", role: .cancel) {}
        } message: {
            Text("结束后将无法再从这台设备恢复本局。")
        }
    }
}

struct BattlePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(BattleLineTheme.surface)
            .padding(.horizontal, 18)
            .frame(minHeight: 50)
            .background(BattleLineTheme.ink.opacity(configuration.isPressed ? 0.78 : 1), in: BattleLineTheme.controlShape)
    }
}

struct BattleSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(BattleLineTheme.ink)
            .padding(.horizontal, 18)
            .frame(minHeight: 50)
            .background(BattleLineTheme.surface.opacity(configuration.isPressed ? 0.72 : 1), in: BattleLineTheme.controlShape)
            .overlay { BattleLineTheme.controlShape.stroke(BattleLineTheme.line) }
    }
}

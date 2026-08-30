import SwiftUI

enum BattleLineTheme {
    static let background = Color(light: 0xEEE4D1, dark: 0x15130F)
    static let surface = Color(light: 0xFFFAF0, dark: 0x252019)
    static let raisedSurface = Color(light: 0xF0E0C2, dark: 0x342B1E)
    static let ink = Color(light: 0x2B241A, dark: 0xF7EDD9)
    static let mutedInk = Color(light: 0x6E6355, dark: 0xBDB19F)
    static let line = Color(light: 0xC8B48C, dark: 0x5E5039)
    static let gold = Color(light: 0x9C6A17, dark: 0xE1B55E)
    static let flag = Color(light: 0xB9322C, dark: 0xDC5A51)

    static let panelShape = RoundedRectangle(cornerRadius: 18, style: .continuous)
    static let controlShape = RoundedRectangle(cornerRadius: 13, style: .continuous)
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(
            UIColor { traits in
                let value = traits.userInterfaceStyle == .dark ? dark : light
                return UIColor(
                    red: CGFloat((value >> 16) & 0xFF) / 255,
                    green: CGFloat((value >> 8) & 0xFF) / 255,
                    blue: CGFloat(value & 0xFF) / 255,
                    alpha: 1
                )
            }
        )
    }
}

struct BattlePanelModifier: ViewModifier {
    var selected = false

    func body(content: Content) -> some View {
        content
            .background(BattleLineTheme.surface, in: BattleLineTheme.panelShape)
            .overlay {
                if selected {
                    BattleLineTheme.panelShape
                        .stroke(BattleLineTheme.gold, lineWidth: 2)
                }
            }
            .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
    }
}

extension View {
    func battlePanel(selected: Bool = false) -> some View {
        modifier(BattlePanelModifier(selected: selected))
    }
}


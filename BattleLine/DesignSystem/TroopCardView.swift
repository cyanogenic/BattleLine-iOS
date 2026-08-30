import SwiftUI

enum TroopColorPresentation: String, CaseIterable, Codable, Sendable {
    case red
    case orange
    case yellow
    case green
    case blue
    case purple

    var localizedName: String {
        switch self {
        case .red: "红"
        case .orange: "橙"
        case .yellow: "黄"
        case .green: "绿"
        case .blue: "蓝"
        case .purple: "紫"
        }
    }

    var color: Color {
        switch self {
        case .red: Color(red: 0.79, green: 0.23, blue: 0.21)
        case .orange: Color(red: 0.85, green: 0.47, blue: 0.14)
        case .yellow: Color(red: 0.83, green: 0.67, blue: 0.09)
        case .green: Color(red: 0.23, green: 0.55, blue: 0.35)
        case .blue: Color(red: 0.20, green: 0.46, blue: 0.69)
        case .purple: Color(red: 0.47, green: 0.34, blue: 0.65)
        }
    }

    var foreground: Color {
        self == .yellow ? Color(red: 0.17, green: 0.14, blue: 0.10) : .white
    }
}

struct TroopCardPresentation: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let color: TroopColorPresentation
    let value: Int

    init(id: String? = nil, color: TroopColorPresentation, value: Int) {
        self.id = id ?? "\(color.rawValue)-\(value)"
        self.color = color
        self.value = value
    }
}

struct TroopCardView: View {
    let card: TroopCardPresentation
    var selected = false
    var compact = false

    var body: some View {
        Text(card.value.formatted())
            .font(compact ? .caption.weight(.semibold) : .headline.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(card.color.foreground)
            .frame(width: compact ? 31 : 43, height: compact ? 46 : 64)
            .background(card.color.color, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(selected ? 0.82 : 0.28), lineWidth: selected ? 2 : 1)
            }
            .shadow(color: .black.opacity(selected ? 0.25 : 0.14), radius: selected ? 6 : 3, y: 2)
            .offset(y: selected ? -4 : 0)
            .accessibilityLabel("\(card.color.localizedName)色 \(card.value)")
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct EmptyTroopSlotView: View {
    var compact = true

    var body: some View {
        Image(systemName: "plus")
            .font(.caption.weight(.medium))
            .foregroundStyle(BattleLineTheme.mutedInk)
            .frame(width: compact ? 31 : 43, height: compact ? 46 : 64)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(BattleLineTheme.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            .accessibilityLabel("空槽位")
    }
}


import SwiftUI

enum AppColors {
    static let background = Color(hex: 0x191919)
    static let columnBackground = Color(hex: 0x252525)
    static let cardBackground = Color(hex: 0x525252)
    static let cardBorder = Color(hex: 0x666666)

    static func statusColor(_ status: TaskStatus) -> Color {
        switch status {
        case .notStarted: return Color(hex: 0x9b9b9b)
        case .inProgress: return Color(hex: 0x6ba3d6)
        case .doToday:    return Color(hex: 0xd4a76a)
        case .completed:  return Color(hex: 0x7bc8a4)
        case .archived:   return Color(hex: 0x9b9b9b)
        }
    }

    static func priorityColor(_ priority: TaskPriority) -> Color {
        switch priority {
        case .high:   return Color(hex: 0xd4837b)
        case .medium: return Color(hex: 0xd4a76a)
        case .low:    return Color(hex: 0x7bc8a4)
        }
    }

    static func categoryColor(_ category: TaskCategory) -> Color {
        switch category {
        case .specra:   return Color(hex: 0x82b5d6)
        case .contract: return Color(hex: 0xd4c07a)
        case .personal: return Color(hex: 0xb8a0d2)
        }
    }
}

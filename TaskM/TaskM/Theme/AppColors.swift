import SwiftUI

enum AppColors {
    static let background = Color(hex: 0x191919)
    static let columnBackground = Color(hex: 0x252525)
    static let cardBackground = Color(hex: 0x2d2d2d)
    static let cardBorder = Color(hex: 0x383838)

    static func statusColor(_ status: TaskStatus) -> Color {
        switch status {
        case .notStarted: return Color(hex: 0x9b9b9b)
        case .inProgress: return Color(hex: 0x2e90fa)
        case .doToday:    return Color(hex: 0xf79009)
        case .completed:  return Color(hex: 0x12b76a)
        case .archived:   return Color(hex: 0x9b9b9b)
        }
    }

    static func priorityColor(_ priority: TaskPriority) -> Color {
        switch priority {
        case .high:   return Color(hex: 0xf04438)
        case .medium: return Color(hex: 0xf79009)
        case .low:    return Color(hex: 0x12b76a)
        }
    }

    static func categoryColor(_ category: TaskCategory) -> Color {
        switch category {
        case .specra:   return Color(hex: 0x5bb8ff)
        case .contract: return Color(hex: 0xf7c948)
        case .personal: return Color(hex: 0xee46bc)
        }
    }
}

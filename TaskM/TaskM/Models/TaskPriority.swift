import Foundation

enum TaskPriority: String, CaseIterable, Codable, Sendable {
    case high = "高"
    case medium = "中"
    case low = "低"

    var sortOrder: Int {
        switch self {
        case .high: return 0
        case .medium: return 1
        case .low: return 2
        }
    }
}

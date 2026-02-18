import Foundation

enum TaskStatus: String, CaseIterable, Codable, Sendable {
    case notStarted = "未着手"
    case inProgress = "進行中"
    case doToday = "今日やる"
    case completed = "完了"
    case archived = "アーカイブ"

    var sortOrder: Int {
        switch self {
        case .notStarted: return 0
        case .inProgress: return 1
        case .doToday: return 2
        case .completed: return 3
        case .archived: return 4
        }
    }

    static var kanbanStatuses: [TaskStatus] {
        [.notStarted, .inProgress, .doToday, .completed]
    }
}

import Foundation
import GRDB

struct TaskItem: Identifiable, Codable, FetchableRecord, PersistableRecord, Sendable, Equatable {
    static let databaseTableName = "tasks"

    var id: Int64?
    var name: String
    var status: String
    var priority: String?
    var category: String?
    var dueDate: String?
    var completedDate: String?
    var parentTaskId: Int64?
    var tags: String?
    var memo: String?
    var createdAt: String?
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, status, priority, category
        case dueDate = "due_date"
        case completedDate = "completed_date"
        case parentTaskId = "parent_task_id"
        case tags, memo
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var taskStatus: TaskStatus {
        get { TaskStatus(rawValue: status) ?? .notStarted }
        set { status = newValue.rawValue }
    }

    var taskPriority: TaskPriority? {
        get { priority.flatMap { TaskPriority(rawValue: $0) } }
        set { priority = newValue?.rawValue }
    }

    var taskCategory: TaskCategory? {
        get { category.flatMap { TaskCategory(rawValue: $0) } }
        set { category = newValue?.rawValue }
    }

    var isSubtask: Bool { parentTaskId != nil }
    var hasMemo: Bool { memo != nil && !(memo?.isEmpty ?? true) }

    var dueDateValue: Date? {
        guard let dueDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dueDate)
    }

    var isOverdue: Bool {
        guard let date = dueDateValue, taskStatus != .completed else { return false }
        return date < Calendar.current.startOfDay(for: Date())
    }

    init(
        id: Int64? = nil,
        name: String = "",
        status: String = TaskStatus.notStarted.rawValue,
        priority: String? = nil,
        category: String? = nil,
        dueDate: String? = nil,
        completedDate: String? = nil,
        parentTaskId: Int64? = nil,
        tags: String? = nil,
        memo: String? = nil,
        createdAt: String? = nil,
        updatedAt: String? = nil
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.priority = priority
        self.category = category
        self.dueDate = dueDate
        self.completedDate = completedDate
        self.parentTaskId = parentTaskId
        self.tags = tags
        self.memo = memo
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

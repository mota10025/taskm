import Foundation
import GRDB

final class DatabaseManager: Sendable {
    static let shared = DatabaseManager()

    let dbPool: DatabasePool

    private nonisolated static let dbPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/workspace/task/tasks.db"
    }()

    nonisolated static var databasePath: String { dbPath }

    private init() {
        do {
            var config = Configuration()
            config.prepareDatabase { db in
                try db.execute(sql: "PRAGMA journal_mode=WAL")
                try db.execute(sql: "PRAGMA busy_timeout=10000")
                try db.execute(sql: "PRAGMA synchronous=NORMAL")
            }
            dbPool = try DatabasePool(path: Self.dbPath, configuration: config)
        } catch {
            fatalError("Cannot open database at \(Self.dbPath): \(error)")
        }
    }

    // MARK: - Read

    nonisolated func fetchParentTasks() throws -> [TaskItem] {
        try dbPool.read { db in
            try TaskItem
                .filter(Column("parent_task_id") == nil)
                .filter(Column("status") != TaskStatus.archived.rawValue)
                .order(
                    sql: """
                        CASE priority
                            WHEN '高' THEN 0 WHEN '中' THEN 1 WHEN '低' THEN 2
                            ELSE 3
                        END ASC,
                        CASE WHEN due_date IS NULL THEN 1 ELSE 0 END ASC,
                        due_date ASC
                    """
                )
                .fetchAll(db)
        }
    }

    nonisolated func fetchAllSubtasks() throws -> [Int64: [TaskItem]] {
        try dbPool.read { db in
            let subtasks = try TaskItem
                .filter(Column("parent_task_id") != nil)
                .order(Column("id"))
                .fetchAll(db)
            return Dictionary(grouping: subtasks) { $0.parentTaskId! }
        }
    }

    nonisolated func fetchSubtasks(forParentId parentId: Int64) throws -> [TaskItem] {
        try dbPool.read { db in
            try TaskItem
                .filter(Column("parent_task_id") == parentId)
                .order(Column("id"))
                .fetchAll(db)
        }
    }

    // MARK: - Write

    nonisolated func updateTaskStatus(_ id: Int64, status: TaskStatus) throws {
        try dbPool.write { db in
            if status == .completed {
                try db.execute(
                    sql: """
                        UPDATE tasks SET status = ?,
                            completed_date = date('now','localtime'),
                            updated_at = datetime('now','localtime')
                        WHERE id = ?
                    """,
                    arguments: [status.rawValue, id]
                )
            } else {
                try db.execute(
                    sql: """
                        UPDATE tasks SET status = ?,
                            updated_at = datetime('now','localtime')
                        WHERE id = ?
                    """,
                    arguments: [status.rawValue, id]
                )
            }
        }
    }

    nonisolated func insertTask(_ task: TaskItem) throws -> Int64 {
        try dbPool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO tasks (name, status, priority, category, due_date, parent_task_id, tags, memo,
                        created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?,
                        datetime('now','localtime'), datetime('now','localtime'))
                """,
                arguments: [
                    task.name, task.status, task.priority, task.category,
                    task.dueDate, task.parentTaskId, task.tags, task.memo,
                ]
            )
            return db.lastInsertedRowID
        }
    }

    nonisolated func updateTask(_ task: TaskItem) throws {
        guard let id = task.id else { return }
        try dbPool.write { db in
            try db.execute(
                sql: """
                    UPDATE tasks SET name=?, status=?, priority=?, category=?,
                        due_date=?, parent_task_id=?, tags=?, memo=?,
                        updated_at=datetime('now','localtime')
                    WHERE id=?
                """,
                arguments: [
                    task.name, task.status, task.priority, task.category,
                    task.dueDate, task.parentTaskId, task.tags, task.memo, id,
                ]
            )
        }
    }

    nonisolated func deleteTask(_ id: Int64) throws {
        try dbPool.write { db in
            try db.execute(sql: "DELETE FROM tasks WHERE parent_task_id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM tasks WHERE id = ?", arguments: [id])
        }
    }

    nonisolated func completeTaskWithSubtasks(_ id: Int64) throws {
        try dbPool.write { db in
            try db.execute(
                sql: """
                    UPDATE tasks SET status='完了', completed_date=date('now','localtime'),
                        updated_at=datetime('now','localtime')
                    WHERE parent_task_id = ? AND status != '完了'
                """,
                arguments: [id]
            )
            try db.execute(
                sql: """
                    UPDATE tasks SET status='完了', completed_date=date('now','localtime'),
                        updated_at=datetime('now','localtime')
                    WHERE id = ?
                """,
                arguments: [id]
            )
        }
    }
}

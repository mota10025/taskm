import Foundation
import Observation

@MainActor
@Observable
final class KanbanViewModel {
    var parentTasks: [TaskItem] = []
    var subtasksByParentId: [Int64: [TaskItem]] = [:]
    var isLoading = false
    var errorMessage: String?

    // フィルタ
    var selectedPriorities: Set<TaskPriority> = []
    var selectedCategories: Set<TaskCategory> = []
    var isFilterActive: Bool { !selectedPriorities.isEmpty || !selectedCategories.isEmpty }

    private var fileWatcher: DatabaseFileWatcher?

    init() {
        loadTasks()
        startWatching()
    }

    func loadTasks() {
        isLoading = true
        let db = DatabaseManager.shared
        Task.detached {
            do {
                let tasks = try db.fetchParentTasks()
                let subtasks = try db.fetchAllSubtasks()
                await MainActor.run {
                    self.parentTasks = tasks
                    self.subtasksByParentId = subtasks
                    self.isLoading = false
                    self.errorMessage = nil
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    func tasksForStatus(_ status: TaskStatus) -> [TaskItem] {
        parentTasks.filter { task in
            guard task.taskStatus == status else { return false }
            if !selectedPriorities.isEmpty {
                guard let p = task.taskPriority, selectedPriorities.contains(p) else { return false }
            }
            if !selectedCategories.isEmpty {
                guard let c = task.taskCategory, selectedCategories.contains(c) else { return false }
            }
            return true
        }
    }

    func clearFilters() {
        selectedPriorities.removeAll()
        selectedCategories.removeAll()
    }

    func subtasks(for task: TaskItem) -> [TaskItem] {
        guard let id = task.id else { return [] }
        return subtasksByParentId[id] ?? []
    }

    func completedSubtaskCount(for task: TaskItem) -> Int {
        subtasks(for: task).filter { $0.taskStatus == .completed }.count
    }

    func moveTask(_ taskId: Int64, to status: TaskStatus) {
        let db = DatabaseManager.shared
        Task.detached {
            do {
                try db.updateTaskStatus(taskId, status: status)
                await MainActor.run { self.loadTasks() }
            } catch {
                await MainActor.run { self.errorMessage = error.localizedDescription }
            }
        }
    }

    func addTask(_ task: TaskItem) {
        let db = DatabaseManager.shared
        Task.detached {
            do {
                _ = try db.insertTask(task)
                await MainActor.run { self.loadTasks() }
            } catch {
                await MainActor.run { self.errorMessage = error.localizedDescription }
            }
        }
    }

    func deleteTask(_ id: Int64) {
        let db = DatabaseManager.shared
        Task.detached {
            do {
                try db.deleteTask(id)
                await MainActor.run { self.loadTasks() }
            } catch {
                await MainActor.run { self.errorMessage = error.localizedDescription }
            }
        }
    }

    private func startWatching() {
        fileWatcher = DatabaseFileWatcher(dbPath: DatabaseManager.databasePath) { [weak self] in
            DispatchQueue.main.async {
                self?.loadTasks()
            }
        }
    }
}

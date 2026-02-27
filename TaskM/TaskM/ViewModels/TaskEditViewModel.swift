import Foundation
import Observation

@MainActor
@Observable
final class TaskEditViewModel {
    var task: TaskItem
    var subtasks: [TaskItem]
    var newSubtaskName = ""
    var showDeleteConfirmation = false
    var showCompleteWithSubtasksConfirmation = false
    var memoEditMode = true

    private let kanbanVM: KanbanViewModel

    var allCategories: [String] { kanbanVM.allCategories }

    init(task: TaskItem, kanbanVM: KanbanViewModel) {
        self.task = task
        self.kanbanVM = kanbanVM
        self.subtasks = kanbanVM.subtasks(for: task)
    }

    var hasIncompleteSubtasks: Bool {
        subtasks.contains { $0.taskStatus != .completed }
    }

    func save() {
        let db = DatabaseManager.shared
        let taskCopy = task
        Task {
            do {
                try await db.updateTask(taskCopy)
                self.kanbanVM.loadTasks()
            } catch {
                self.kanbanVM.errorMessage = error.localizedDescription
            }
        }
    }

    func delete() {
        guard let id = task.id else { return }
        kanbanVM.deleteTask(id)
    }

    func addSubtask() {
        guard !newSubtaskName.isEmpty, let parentId = task.id else { return }
        let subtask = TaskItem(name: newSubtaskName, parentTaskId: parentId)
        let db = DatabaseManager.shared
        Task {
            do {
                _ = try await db.insertTask(subtask)
                let updated = try await db.fetchSubtasks(forParentId: parentId)
                self.subtasks = updated
                self.newSubtaskName = ""
                self.kanbanVM.loadTasks()
            } catch {
                self.kanbanVM.errorMessage = error.localizedDescription
            }
        }
    }

    func toggleSubtask(_ subtask: TaskItem) {
        guard let id = subtask.id else { return }
        let newStatus: TaskStatus = subtask.taskStatus == .completed ? .notStarted : .completed
        let db = DatabaseManager.shared
        Task {
            do {
                try await db.updateTaskStatus(id, status: newStatus)
                if let parentId = subtask.parentTaskId {
                    let updated = try await db.fetchSubtasks(forParentId: parentId)
                    self.subtasks = updated
                    self.kanbanVM.loadTasks()
                }
            } catch {
                self.kanbanVM.errorMessage = error.localizedDescription
            }
        }
    }

    func deleteSubtask(_ subtask: TaskItem) {
        guard let id = subtask.id else { return }
        let db = DatabaseManager.shared
        Task {
            do {
                try await db.deleteTask(id)
                if let parentId = subtask.parentTaskId {
                    let updated = try await db.fetchSubtasks(forParentId: parentId)
                    self.subtasks = updated
                    self.kanbanVM.loadTasks()
                }
            } catch {
                self.kanbanVM.errorMessage = error.localizedDescription
            }
        }
    }

    func completeParentWithSubtasks() {
        guard let id = task.id else { return }
        let db = DatabaseManager.shared
        Task {
            do {
                try await db.completeTaskWithSubtasks(id)
                self.kanbanVM.loadTasks()
            } catch {
                self.kanbanVM.errorMessage = error.localizedDescription
            }
        }
    }
}

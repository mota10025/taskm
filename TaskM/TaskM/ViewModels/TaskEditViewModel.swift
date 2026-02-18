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
        Task.detached {
            do {
                try db.updateTask(taskCopy)
                await MainActor.run { self.kanbanVM.loadTasks() }
            } catch {
                await MainActor.run { self.kanbanVM.errorMessage = error.localizedDescription }
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
        Task.detached {
            do {
                _ = try db.insertTask(subtask)
                let updated = try db.fetchSubtasks(forParentId: parentId)
                await MainActor.run {
                    self.subtasks = updated
                    self.newSubtaskName = ""
                    self.kanbanVM.loadTasks()
                }
            } catch {
                await MainActor.run { self.kanbanVM.errorMessage = error.localizedDescription }
            }
        }
    }

    func toggleSubtask(_ subtask: TaskItem) {
        guard let id = subtask.id else { return }
        let newStatus: TaskStatus = subtask.taskStatus == .completed ? .notStarted : .completed
        let db = DatabaseManager.shared
        Task.detached {
            do {
                try db.updateTaskStatus(id, status: newStatus)
                if let parentId = subtask.parentTaskId {
                    let updated = try db.fetchSubtasks(forParentId: parentId)
                    await MainActor.run {
                        self.subtasks = updated
                        self.kanbanVM.loadTasks()
                    }
                }
            } catch {
                await MainActor.run { self.kanbanVM.errorMessage = error.localizedDescription }
            }
        }
    }

    func deleteSubtask(_ subtask: TaskItem) {
        guard let id = subtask.id else { return }
        let db = DatabaseManager.shared
        Task.detached {
            do {
                try db.deleteTask(id)
                if let parentId = subtask.parentTaskId {
                    let updated = try db.fetchSubtasks(forParentId: parentId)
                    await MainActor.run {
                        self.subtasks = updated
                        self.kanbanVM.loadTasks()
                    }
                }
            } catch {
                await MainActor.run { self.kanbanVM.errorMessage = error.localizedDescription }
            }
        }
    }

    func completeParentWithSubtasks() {
        guard let id = task.id else { return }
        let db = DatabaseManager.shared
        Task.detached {
            do {
                try db.completeTaskWithSubtasks(id)
                await MainActor.run { self.kanbanVM.loadTasks() }
            } catch {
                await MainActor.run { self.kanbanVM.errorMessage = error.localizedDescription }
            }
        }
    }
}

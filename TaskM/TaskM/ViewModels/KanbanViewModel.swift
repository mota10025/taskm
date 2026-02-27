import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class KanbanViewModel {
    var parentTasks: [TaskItem] = []
    var subtasksByParentId: [Int64: [TaskItem]] = [:]
    var categories: [CategoryItem] = []
    var isLoading = false
    var errorMessage: String?

    // フィルタ
    var selectedPriorities: Set<TaskPriority> = []
    var selectedCategories: Set<String> = []
    var isFilterActive: Bool { !selectedPriorities.isEmpty || !selectedCategories.isEmpty }

    // DBのcategoriesテーブルに登録されているカテゴリのみ
    var allCategories: [String] {
        categories.map(\.name)
    }

    private var pollingTask: Task<Void, Never>?

    init() {
        loadTasks()
        startPolling()
    }

    func loadTasks() {
        isLoading = true
        let db = DatabaseManager.shared
        Task {
            do {
                let result = try await db.fetchParentTasksWithCategories()
                let subtasks = try await db.fetchAllSubtasks()
                self.parentTasks = result.tasks
                self.categories = result.categories
                self.subtasksByParentId = subtasks
                self.isLoading = false
                self.errorMessage = nil
            } catch {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    func categoryColor(for name: String) -> Color {
        if let cat = categories.first(where: { $0.name == name }) {
            return Color(hexString: cat.color)
        }
        return AppColors.categoryColor(name)
    }

    func categoryTextColor(for name: String) -> Color {
        if let cat = categories.first(where: { $0.name == name }) {
            return Color(hexString: cat.textColor)
        }
        return Color(hex: 0x2a2a2a)
    }

    func tasksForStatus(_ status: TaskStatus) -> [TaskItem] {
        parentTasks.filter { task in
            guard task.taskStatus == status else { return false }
            if !selectedPriorities.isEmpty {
                guard let p = task.taskPriority, selectedPriorities.contains(p) else { return false }
            }
            if !selectedCategories.isEmpty {
                guard let c = task.category, selectedCategories.contains(c) else { return false }
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
        Task {
            do {
                try await db.updateTaskStatus(taskId, status: status)
                self.loadTasks()
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func addTask(_ task: TaskItem) {
        let db = DatabaseManager.shared
        Task {
            do {
                _ = try await db.insertTask(task)
                self.loadTasks()
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func deleteTask(_ id: Int64) {
        let db = DatabaseManager.shared
        Task {
            do {
                try await db.deleteTask(id)
                self.loadTasks()
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    private func startPolling() {
        pollingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                if !Task.isCancelled {
                    self.loadTasks()
                }
            }
        }
    }
}

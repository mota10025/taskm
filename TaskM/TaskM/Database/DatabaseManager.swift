import Foundation

// API response wrapper
private struct APIResponse<T: Decodable>: Decodable {
    let success: Bool
    let data: T?
    let error: String?
}

private struct TaskAPIData: Decodable {
    let id: Int64
    let name: String
    let status: String
    let priority: String?
    let category: String?
    let due_date: String?
    let completed_date: String?
    let parent_task_id: Int64?
    let tags: String?
    let memo: String?
    let created_at: String
    let updated_at: String
    let subtasks: [TaskAPIData]?

    func toTaskItem() -> TaskItem {
        TaskItem(
            id: id, name: name, status: status,
            priority: priority, category: category,
            dueDate: due_date, completedDate: completed_date,
            parentTaskId: parent_task_id, tags: tags, memo: memo,
            createdAt: created_at, updatedAt: updated_at
        )
    }
}

private struct CreateResponse: Decodable {
    let id: Int64
}

// GET /tasks レスポンス（tasks + categories を同時に返す）
private struct TaskListResponse: Decodable {
    let success: Bool
    let data: [TaskAPIData]
    let categories: [CategoryItem]?
    let error: String?
}

final class DatabaseManager: Sendable {
    static let shared = DatabaseManager()

    private let apiURL: String
    private let apiKey: String

    private init() {
        self.apiURL = Secrets.apiURL
        self.apiKey = Secrets.apiKey
    }

    // MARK: - API Helper

    private func request<T: Decodable>(
        path: String,
        method: String = "GET",
        body: [String: Any]? = nil
    ) async throws -> T {
        guard let url = URL(string: "\(apiURL)/api\(path)") else {
            throw APIError.invalidURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await URLSession.shared.data(for: req)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let errorResponse = try? JSONDecoder().decode(APIResponse<String>.self, from: data)
            throw APIError.serverError(errorResponse?.error ?? "Unknown error")
        }

        let decoded = try JSONDecoder().decode(APIResponse<T>.self, from: data)
        guard decoded.success, let result = decoded.data else {
            throw APIError.serverError(decoded.error ?? "Unknown error")
        }
        return result
    }

    private func requestVoid(
        path: String,
        method: String = "GET",
        body: [String: Any]? = nil
    ) async throws {
        guard let url = URL(string: "\(apiURL)/api\(path)") else {
            throw APIError.invalidURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await URLSession.shared.data(for: req)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let errorResponse = try? JSONDecoder().decode(APIResponse<String>.self, from: data)
            throw APIError.serverError(errorResponse?.error ?? "Unknown error")
        }
    }

    // MARK: - Read

    func fetchParentTasksWithCategories() async throws -> (tasks: [TaskItem], categories: [CategoryItem]) {
        guard let url = URL(string: "\(apiURL)/api/tasks?include_subtasks=false") else {
            throw APIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let errorResponse = try? JSONDecoder().decode(APIResponse<String>.self, from: data)
            throw APIError.serverError(errorResponse?.error ?? "Unknown error")
        }

        let decoded = try JSONDecoder().decode(TaskListResponse.self, from: data)
        guard decoded.success else {
            throw APIError.serverError(decoded.error ?? "Unknown error")
        }

        let tasks = decoded.data
            .filter { $0.parent_task_id == nil && $0.status != "アーカイブ" }
            .map { $0.toTaskItem() }
        let categories = decoded.categories ?? []
        return (tasks, categories)
    }

    func fetchAllSubtasks() async throws -> [Int64: [TaskItem]] {
        let tasks: [TaskAPIData] = try await request(
            path: "/tasks?show_all=true&include_subtasks=true"
        )
        var result: [Int64: [TaskItem]] = [:]
        for task in tasks {
            if let subtasks = task.subtasks, !subtasks.isEmpty {
                result[task.id] = subtasks.map { $0.toTaskItem() }
            }
        }
        return result
    }

    func fetchSubtasks(forParentId parentId: Int64) async throws -> [TaskItem] {
        let task: TaskAPIData = try await request(path: "/tasks/\(parentId)")
        return task.subtasks?.map { $0.toTaskItem() } ?? []
    }

    // MARK: - Write

    func updateTaskStatus(_ id: Int64, status: TaskStatus) async throws {
        if status == .completed {
            try await requestVoid(
                path: "/tasks/\(id)/complete",
                method: "POST",
                body: ["complete_subtasks": false]
            )
        } else {
            try await requestVoid(
                path: "/tasks/\(id)",
                method: "PUT",
                body: ["status": status.rawValue]
            )
        }
    }

    func insertTask(_ task: TaskItem) async throws -> Int64 {
        var body: [String: Any] = ["name": task.name]
        body["status"] = task.status
        if let p = task.priority { body["priority"] = p }
        if let c = task.category { body["category"] = c }
        if let d = task.dueDate { body["due_date"] = d }
        if let t = task.tags { body["tags"] = t }
        if let m = task.memo { body["memo"] = m }
        if let pid = task.parentTaskId { body["parent_task_id"] = pid }

        let result: CreateResponse = try await request(
            path: "/tasks",
            method: "POST",
            body: body
        )
        return result.id
    }

    func updateTask(_ task: TaskItem) async throws {
        guard let id = task.id else { return }
        var body: [String: Any] = [
            "name": task.name,
            "status": task.status,
        ]
        body["priority"] = task.priority as Any
        body["category"] = task.category as Any
        body["due_date"] = task.dueDate as Any
        body["tags"] = task.tags as Any
        body["memo"] = task.memo as Any

        try await requestVoid(
            path: "/tasks/\(id)",
            method: "PUT",
            body: body
        )
    }

    func deleteTask(_ id: Int64) async throws {
        try await requestVoid(
            path: "/tasks/\(id)",
            method: "DELETE"
        )
    }

    func completeTaskWithSubtasks(_ id: Int64) async throws {
        try await requestVoid(
            path: "/tasks/\(id)/complete",
            method: "POST",
            body: ["complete_subtasks": true]
        )
    }

    // MARK: - Categories

    func createCategory(name: String, color: String, textColor: String = "#2a2a2a") async throws {
        try await requestVoid(
            path: "/categories",
            method: "POST",
            body: ["name": name, "color": color, "text_color": textColor]
        )
    }

    func updateCategory(oldName: String, newName: String? = nil, newColor: String? = nil, newTextColor: String? = nil) async throws {
        var body: [String: Any] = [:]
        if let n = newName { body["name"] = n }
        if let c = newColor { body["color"] = c }
        if let tc = newTextColor { body["text_color"] = tc }
        guard !body.isEmpty else { return }
        let encoded = oldName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? oldName
        try await requestVoid(
            path: "/categories/\(encoded)",
            method: "PUT",
            body: body
        )
    }

    func deleteCategory(name: String) async throws {
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        try await requestVoid(
            path: "/categories/\(encoded)",
            method: "DELETE"
        )
    }
}

enum APIError: LocalizedError {
    case invalidURL
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid API URL"
        case .serverError(let msg): return msg
        }
    }
}

import SwiftUI

struct TaskAddFormView: View {
    let status: TaskStatus
    let onSave: (TaskItem) -> Void
    let onCancel: () -> Void

    @State private var name = ""
    @State private var dueDate = ""
    @State private var priority: String? = nil
    @State private var category: String? = nil

    var body: some View {
        VStack(spacing: 8) {
            TextField("タスク名", text: $name)
                .textFieldStyle(.plain)
                .padding(8)
                .background(Color.white.opacity(0.05))
                .cornerRadius(6)
                .foregroundColor(.white)
                .onSubmit { addTask() }

            HStack(spacing: 8) {
                TextField("期限 (YYYY-MM-DD)", text: $dueDate)
                    .textFieldStyle(.plain)
                    .padding(6)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(4)
                    .foregroundColor(.white)
                    .frame(width: 130)

                Picker("", selection: $priority) {
                    Text("優先度").tag(nil as String?)
                    ForEach(TaskPriority.allCases, id: \.self) { p in
                        Text(p.rawValue).tag(p.rawValue as String?)
                    }
                }
                .frame(width: 70)

                Picker("", selection: $category) {
                    Text("カテゴリ").tag(nil as String?)
                    ForEach(TaskCategory.allCases, id: \.self) { c in
                        Text(c.rawValue).tag(c.rawValue as String?)
                    }
                }
                .frame(width: 80)
            }

            HStack {
                Spacer()
                Button("キャンセル") { onCancel() }
                    .buttonStyle(.plain)
                    .foregroundColor(.gray)
                Button("追加") { addTask() }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(8)
        .background(AppColors.cardBackground)
        .cornerRadius(8)
    }

    private func addTask() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let task = TaskItem(
            name: trimmed,
            status: status.rawValue,
            priority: priority,
            category: category,
            dueDate: dueDate.isEmpty ? nil : dueDate
        )
        onSave(task)
    }
}

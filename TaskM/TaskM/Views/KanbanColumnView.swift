import SwiftUI

struct KanbanColumnView: View {
    let status: TaskStatus
    let tasks: [TaskItem]
    let viewModel: KanbanViewModel
    let onCardTap: (TaskItem) -> Void

    @State private var showAddForm = false
    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // カラムヘッダー
            HStack(spacing: 8) {
                Circle()
                    .fill(AppColors.statusColor(status))
                    .frame(width: 10, height: 10)

                Text(status.rawValue)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)

                Text("\(tasks.count)")
                    .font(.system(size: 13))
                    .foregroundColor(.gray)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(8)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)

            // カード一覧
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(tasks) { task in
                        TaskCardView(
                            task: task,
                            subtasks: viewModel.subtasks(for: task),
                            completedCount: viewModel.completedSubtaskCount(for: task),
                            categoryColor: task.category.map { viewModel.categoryColor(for: $0) },
                            categoryTextColor: task.category.map { viewModel.categoryTextColor(for: $0) }
                        )
                        .onTapGesture { onCardTap(task) }
                        .draggable(task.id ?? 0) {
                            TaskCardView(
                                task: task,
                                subtasks: viewModel.subtasks(for: task),
                                completedCount: viewModel.completedSubtaskCount(for: task),
                                categoryColor: task.category.map { viewModel.categoryColor(for: $0) },
                                categoryTextColor: task.category.map { viewModel.categoryTextColor(for: $0) }
                            )
                            .frame(width: 240)
                            .opacity(0.8)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }

            // 新規タスク追加
            if showAddForm {
                TaskAddFormView(
                    status: status,
                    categories: viewModel.allCategories,
                    onSave: { task in
                        viewModel.addTask(task)
                        showAddForm = false
                    },
                    onCancel: { showAddForm = false }
                )
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            } else {
                Button(action: { showAddForm = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 13))
                        Text("新規タスク")
                            .font(.system(size: 14))
                    }
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
        .background(AppColors.columnBackground)
        .cornerRadius(8)
        .dropDestination(for: Int64.self) { droppedIds, _ in
            for id in droppedIds {
                viewModel.moveTask(id, to: status)
            }
            return true
        } isTargeted: { targeted in
            isTargeted = targeted
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isTargeted ? AppColors.statusColor(status).opacity(0.5) : Color.clear,
                    lineWidth: 2
                )
        )
    }
}

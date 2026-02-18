import SwiftUI

struct TaskCardView: View {
    let task: TaskItem
    let subtasks: [TaskItem]
    let completedCount: Int
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(task.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(2)

            HStack(spacing: 6) {
                if let priority = task.taskPriority {
                    Text(priority.rawValue)
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppColors.priorityColor(priority).opacity(0.15))
                        .foregroundColor(AppColors.priorityColor(priority))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(AppColors.priorityColor(priority).opacity(0.3), lineWidth: 1)
                        )
                        .cornerRadius(4)
                }

                if let category = task.taskCategory {
                    Text(category.rawValue)
                        .font(.system(size: 10))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppColors.categoryColor(category).opacity(0.1))
                        .foregroundColor(AppColors.categoryColor(category))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(AppColors.categoryColor(category).opacity(0.3), lineWidth: 1)
                        )
                        .cornerRadius(4)
                }

                Spacer()

                if task.hasMemo {
                    Image(systemName: "doc.text")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                }
            }

            if let dueDate = task.dueDate {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.system(size: 10))
                    Text(dueDate.replacingOccurrences(of: "-", with: "/"))
                        .font(.system(size: 11))
                }
                .foregroundColor(task.isOverdue ? Color(hex: 0xf04438) : .gray)
            }

            if !subtasks.isEmpty {
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                    HStack(spacing: 4) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9))
                        Text("サブタスク (\(completedCount)/\(subtasks.count))")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.gray)
                }
                .buttonStyle(.plain)

                if isExpanded {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(subtasks) { subtask in
                            SubtaskRowView(subtask: subtask)
                        }
                    }
                    .padding(.leading, 8)
                    .transition(.opacity)
                }
            }
        }
        .padding(10)
        .background(AppColors.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(AppColors.cardBorder, lineWidth: 1)
        )
        .cornerRadius(6)
    }
}

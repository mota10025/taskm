import SwiftUI

struct TaskCardView: View {
    let task: TaskItem
    let subtasks: [TaskItem]
    let completedCount: Int
    var categoryColor: Color?
    var categoryTextColor: Color?
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(task.name)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color(hex: 0xe8e8e8))
                .lineLimit(2)

            HStack(spacing: 6) {
                if let priority = task.taskPriority {
                    Text(priority.rawValue)
                        .font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(AppColors.priorityColor(priority))
                        .foregroundColor(Color(hex: 0x2a2a2a))
                        .cornerRadius(4)
                }

                if let category = task.category {
                    Text(category)
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(categoryColor ?? AppColors.categoryColor(category))
                        .foregroundColor(categoryTextColor ?? Color(hex: 0x2a2a2a))
                        .cornerRadius(4)
                }

                Spacer()

                if task.hasMemo {
                    Image(systemName: "doc.text")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
            }

            // タグ
            if let tags = task.tags, !tags.isEmpty {
                let tagList = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                if !tagList.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(tagList, id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 11))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.85))
                                .foregroundColor(Color(hex: 0x333333))
                                .cornerRadius(3)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3)
                                        .stroke(Color.black.opacity(0.15), lineWidth: 1)
                                )
                        }
                    }
                }
            }

            if let dueDate = task.dueDate {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.system(size: 12, weight: task.isOverdue ? .bold : .regular))
                    Text(dueDate.replacingOccurrences(of: "-", with: "/"))
                        .font(.system(size: 13, weight: task.isOverdue ? .bold : .regular))
                }
                .foregroundColor(task.isOverdue ? Color(hex: 0xe8c84a) : Color(hex: 0xcccccc))
            }

            if !subtasks.isEmpty {
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                    HStack(spacing: 4) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 11))
                        Text("サブタスク (\(completedCount)/\(subtasks.count))")
                            .font(.system(size: 13))
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
        .padding(12)
        .background(AppColors.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(AppColors.cardBorder, lineWidth: 1)
        )
        .cornerRadius(6)
    }
}

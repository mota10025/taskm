import SwiftUI

struct SubtaskRowView: View {
    let subtask: TaskItem

    var body: some View {
        HStack(spacing: 6) {
            Image(
                systemName: subtask.taskStatus == .completed
                    ? "checkmark.circle.fill" : "circle"
            )
            .font(.system(size: 12))
            .foregroundColor(
                subtask.taskStatus == .completed
                    ? AppColors.statusColor(.completed) : .gray
            )

            Text(subtask.name)
                .font(.system(size: 11))
                .foregroundColor(subtask.taskStatus == .completed ? .gray : .white)
                .strikethrough(subtask.taskStatus == .completed)
                .lineLimit(1)
        }
    }
}

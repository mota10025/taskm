import SwiftUI

struct FilterBarView: View {
    @Bindable var viewModel: KanbanViewModel

    var body: some View {
        HStack(spacing: 12) {
            // 優先度フィルタ
            HStack(spacing: 4) {
                Text("優先度")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
                ForEach(TaskPriority.allCases, id: \.self) { priority in
                    FilterChip(
                        label: priority.rawValue,
                        color: AppColors.priorityColor(priority),
                        isSelected: viewModel.selectedPriorities.contains(priority)
                    ) {
                        if viewModel.selectedPriorities.contains(priority) {
                            viewModel.selectedPriorities.remove(priority)
                        } else {
                            viewModel.selectedPriorities.insert(priority)
                        }
                    }
                }
            }

            Divider()
                .frame(height: 16)
                .background(Color.white.opacity(0.15))

            // カテゴリフィルタ
            HStack(spacing: 4) {
                Text("カテゴリ")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
                ForEach(TaskCategory.allCases, id: \.self) { category in
                    FilterChip(
                        label: category.rawValue,
                        color: AppColors.categoryColor(category),
                        isSelected: viewModel.selectedCategories.contains(category)
                    ) {
                        if viewModel.selectedCategories.contains(category) {
                            viewModel.selectedCategories.remove(category)
                        } else {
                            viewModel.selectedCategories.insert(category)
                        }
                    }
                }
            }

            Spacer()

            // クリアボタン
            if viewModel.isFilterActive {
                Button(action: { viewModel.clearFilters() }) {
                    HStack(spacing: 3) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                        Text("クリア")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

private struct FilterChip: View {
    let label: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: isSelected ? .bold : .regular))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(isSelected ? color.opacity(0.2) : Color.white.opacity(0.05))
                .foregroundColor(isSelected ? color : .gray)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isSelected ? color.opacity(0.5) : Color.clear, lineWidth: 1)
                )
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }
}

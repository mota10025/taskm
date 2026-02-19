import SwiftUI

struct FilterBarView: View {
    @Bindable var viewModel: KanbanViewModel

    var body: some View {
        HStack(spacing: 12) {
            // 優先度フィルタ
            HStack(spacing: 6) {
                Text("優先度")
                    .font(.system(size: 13))
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
                .frame(height: 20)
                .background(Color.white.opacity(0.15))

            // カテゴリフィルタ
            HStack(spacing: 6) {
                Text("カテゴリ")
                    .font(.system(size: 13))
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
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                        Text("クリア")
                            .font(.system(size: 13))
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
                .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? color.opacity(0.25) : Color(hex: 0x3a3a3a))
                .foregroundColor(isSelected ? color : Color(hex: 0xcccccc))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(isSelected ? color.opacity(0.6) : Color(hex: 0x555555), lineWidth: 1)
                )
                .cornerRadius(5)
        }
        .buttonStyle(.plain)
    }
}

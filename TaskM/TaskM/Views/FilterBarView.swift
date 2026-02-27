import SwiftUI

struct FilterBarView: View {
    @Bindable var viewModel: KanbanViewModel
    @State private var showCategoryPopover = false

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

            // カテゴリフィルタ（ポップオーバー）
            Button(action: { showCategoryPopover.toggle() }) {
                HStack(spacing: 6) {
                    Text("カテゴリ")
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                    if !viewModel.selectedCategories.isEmpty {
                        Text("\(viewModel.selectedCategories.count)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color(hex: 0x6ba3d6))
                            .cornerRadius(8)
                    }
                    Text("▾")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(hex: 0x3a3a3a))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color(hex: 0x555555), lineWidth: 1)
                )
                .cornerRadius(5)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showCategoryPopover, arrowEdge: .bottom) {
                CategoryFilterPopover(viewModel: viewModel)
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

private struct CategoryFilterPopover: View {
    @Bindable var viewModel: KanbanViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(viewModel.allCategories, id: \.self) { category in
                let isSelected = viewModel.selectedCategories.contains(category)
                let color = viewModel.categoryColor(for: category)

                Button(action: {
                    if isSelected {
                        viewModel.selectedCategories.remove(category)
                    } else {
                        viewModel.selectedCategories.insert(category)
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                            .font(.system(size: 14))
                            .foregroundColor(isSelected ? Color(hex: 0x6ba3d6) : .gray)
                            .frame(width: 16)

                        Circle()
                            .fill(color)
                            .frame(width: 8, height: 8)

                        Text(category)
                            .font(.system(size: 13))
                            .foregroundColor(.primary)

                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if category != viewModel.allCategories.last {
                    Divider().padding(.horizontal, 8)
                }
            }
        }
        .padding(.vertical, 4)
        .frame(minWidth: 180)
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

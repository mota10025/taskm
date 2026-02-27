import SwiftUI
import MarkdownUI

struct TaskEditView: View {
    @Bindable var viewModel: TaskEditViewModel
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // ヘッダー
                HStack {
                    Text("タスク編集")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // タスク名
                        VStack(alignment: .leading, spacing: 4) {
                            Text("タスク名")
                                .font(.system(size: 11))
                                .foregroundColor(.gray)
                            TextField("タスク名", text: $viewModel.task.name)
                                .textFieldStyle(.plain)
                                .padding(8)
                                .background(Color.white.opacity(0.05))
                                .cornerRadius(6)
                                .foregroundColor(.white)
                        }

                        // ステータス・優先度・カテゴリ
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("ステータス")
                                    .font(.system(size: 11))
                                    .foregroundColor(.gray)
                                Picker("", selection: $viewModel.task.status) {
                                    ForEach(TaskStatus.kanbanStatuses, id: \.self) { s in
                                        Text(s.rawValue).tag(s.rawValue)
                                    }
                                }
                                .labelsHidden()
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("優先度")
                                    .font(.system(size: 11))
                                    .foregroundColor(.gray)
                                Picker("", selection: $viewModel.task.priority) {
                                    Text("なし").tag(nil as String?)
                                    ForEach(TaskPriority.allCases, id: \.self) { p in
                                        Text(p.rawValue).tag(p.rawValue as String?)
                                    }
                                }
                                .labelsHidden()
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("カテゴリ")
                                    .font(.system(size: 11))
                                    .foregroundColor(.gray)
                                Picker("", selection: $viewModel.task.category) {
                                    Text("なし").tag(nil as String?)
                                    ForEach(viewModel.allCategories, id: \.self) { c in
                                        Text(c).tag(c as String?)
                                    }
                                }
                                .labelsHidden()
                            }
                        }

                        // 期限
                        VStack(alignment: .leading, spacing: 4) {
                            Text("期限")
                                .font(.system(size: 11))
                                .foregroundColor(.gray)
                            HStack {
                                if viewModel.task.dueDate != nil {
                                    DatePicker("", selection: Binding(
                                        get: {
                                            let formatter = DateFormatter()
                                            formatter.dateFormat = "yyyy-MM-dd"
                                            return formatter.date(from: viewModel.task.dueDate ?? "") ?? Date()
                                        },
                                        set: {
                                            let formatter = DateFormatter()
                                            formatter.dateFormat = "yyyy-MM-dd"
                                            viewModel.task.dueDate = formatter.string(from: $0)
                                        }
                                    ), displayedComponents: .date)
                                    .labelsHidden()

                                    Button(action: { viewModel.task.dueDate = nil }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.gray)
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    Button(action: {
                                        let formatter = DateFormatter()
                                        formatter.dateFormat = "yyyy-MM-dd"
                                        viewModel.task.dueDate = formatter.string(from: Date())
                                    }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "calendar.badge.plus")
                                            Text("期限を設定")
                                        }
                                        .font(.system(size: 13))
                                        .foregroundColor(.gray)
                                        .padding(8)
                                        .background(Color.white.opacity(0.05))
                                        .cornerRadius(6)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        // タグ
                        VStack(alignment: .leading, spacing: 4) {
                            Text("タグ")
                                .font(.system(size: 11))
                                .foregroundColor(.gray)
                            TextField("カンマ区切り", text: Binding(
                                get: { viewModel.task.tags ?? "" },
                                set: { viewModel.task.tags = $0.isEmpty ? nil : $0 }
                            ))
                            .textFieldStyle(.plain)
                            .padding(8)
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(6)
                            .foregroundColor(.white)
                        }

                        Divider().background(Color.white.opacity(0.1))

                        // メモ
                        memoSection

                        // サブタスク（親タスクのみ）
                        if !viewModel.task.isSubtask {
                            Divider().background(Color.white.opacity(0.1))
                            subtaskSection
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }

                Divider().background(Color.white.opacity(0.1))

                // フッター
                HStack {
                    Button(action: {
                        viewModel.showDeleteConfirmation = true
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                            Text("削除")
                        }
                        .foregroundColor(Color(hex: 0xf04438))
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button("キャンセル") { onDismiss() }
                        .buttonStyle(.plain)
                        .foregroundColor(.gray)

                    Button("保存") {
                        // 完了に変更 & 未完了サブタスクあり → 確認
                        if viewModel.task.taskStatus == .completed && viewModel.hasIncompleteSubtasks {
                            viewModel.showCompleteWithSubtasksConfirmation = true
                        } else {
                            viewModel.save()
                            onDismiss()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(16)
            }
        }
        .alert("タスクを削除", isPresented: $viewModel.showDeleteConfirmation) {
            Button("削除", role: .destructive) {
                viewModel.delete()
                onDismiss()
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            if !viewModel.subtasks.isEmpty {
                Text("サブタスクも一緒に削除されます。削除しますか？")
            } else {
                Text("このタスクを削除しますか？")
            }
        }
        .alert("未完了のサブタスクがあります", isPresented: $viewModel.showCompleteWithSubtasksConfirmation) {
            Button("すべて完了にする") {
                viewModel.completeParentWithSubtasks()
                onDismiss()
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("未完了のサブタスクをすべて完了にしますか？")
        }
    }

    // MARK: - メモセクション

    @ViewBuilder
    private var memoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("メモ")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
                Spacer()
                Picker("", selection: $viewModel.memoEditMode) {
                    Text("編集").tag(true)
                    Text("プレビュー").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
            }

            if viewModel.memoEditMode {
                TextEditor(text: Binding(
                    get: { viewModel.task.memo ?? "" },
                    set: { viewModel.task.memo = $0.isEmpty ? nil : $0 }
                ))
                .font(.system(size: 13, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color.white.opacity(0.05))
                .cornerRadius(6)
                .foregroundColor(.white)
                .frame(minHeight: 120)
            } else {
                if let memo = viewModel.task.memo, !memo.isEmpty {
                    ScrollView {
                        Markdown(memo)
                            .markdownTheme(.gitHub)
                            .padding(8)
                    }
                    .frame(minHeight: 120)
                    .background(Color.white.opacity(0.03))
                    .cornerRadius(6)
                } else {
                    Text("メモなし")
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                        .padding(8)
                        .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
                        .background(Color.white.opacity(0.03))
                        .cornerRadius(6)
                }
            }
        }
    }

    // MARK: - サブタスクセクション

    @ViewBuilder
    private var subtaskSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("サブタスク")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)

                if !viewModel.subtasks.isEmpty {
                    let completed = viewModel.subtasks.filter { $0.taskStatus == .completed }.count
                    Text("\(completed)/\(viewModel.subtasks.count)")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }
            }

            ForEach(viewModel.subtasks) { subtask in
                HStack(spacing: 8) {
                    Button(action: { viewModel.toggleSubtask(subtask) }) {
                        Image(
                            systemName: subtask.taskStatus == .completed
                                ? "checkmark.circle.fill" : "circle"
                        )
                        .font(.system(size: 14))
                        .foregroundColor(
                            subtask.taskStatus == .completed
                                ? AppColors.statusColor(.completed) : .gray
                        )
                    }
                    .buttonStyle(.plain)

                    Text(subtask.name)
                        .font(.system(size: 13))
                        .foregroundColor(subtask.taskStatus == .completed ? .gray : .white)
                        .strikethrough(subtask.taskStatus == .completed)

                    Spacer()

                    Button(action: { viewModel.deleteSubtask(subtask) }) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 4)
            }

            // サブタスク追加
            HStack(spacing: 8) {
                TextField("サブタスクを追加...", text: $viewModel.newSubtaskName)
                    .textFieldStyle(.plain)
                    .padding(6)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(4)
                    .foregroundColor(.white)
                    .onSubmit { viewModel.addSubtask() }

                Button(action: { viewModel.addSubtask() }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(AppColors.statusColor(.inProgress))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.newSubtaskName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}

//
//  ContentView.swift
//  TaskM
//
//  Created by Miwa Takayoshi on 2026/02/18.
//

import SwiftUI

struct ContentView: View {
    @Bindable var viewModel: KanbanViewModel
    @State private var editingTask: TaskItem?
    @State private var showSettings = false

    init(viewModel: KanbanViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()

            if viewModel.isLoading && viewModel.parentTasks.isEmpty {
                ProgressView()
                    .progressViewStyle(.circular)
            } else {
                VStack(spacing: 0) {
                    // ヘッダー
                    HStack {
                        Text("TaskM")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)

                        Button(action: { showSettings = true }) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                        }
                        .buttonStyle(.plain)

                        Spacer()
                        if let error = viewModel.errorMessage {
                            Text(error)
                                .font(.system(size: 13))
                                .foregroundColor(Color(hex: 0xf04438))
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    // フィルタバー
                    FilterBarView(viewModel: viewModel)

                    // カンバンボード
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(TaskStatus.kanbanStatuses, id: \.self) { status in
                            KanbanColumnView(
                                status: status,
                                tasks: viewModel.tasksForStatus(status),
                                viewModel: viewModel,
                                onCardTap: { task in editingTask = task }
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
            }
        }
        .sheet(item: $editingTask) { task in
            TaskEditView(
                viewModel: TaskEditViewModel(task: task, kanbanVM: viewModel),
                onDismiss: { editingTask = nil }
            )
            .frame(minWidth: 500, minHeight: 500)
        }
        .sheet(isPresented: $showSettings) {
            CategorySettingsView(viewModel: viewModel)
                .frame(minWidth: 400, minHeight: 350)
        }
    }
}

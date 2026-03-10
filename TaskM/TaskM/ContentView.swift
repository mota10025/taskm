//
//  ContentView.swift
//  TaskM
//
//  Created by Miwa Takayoshi on 2026/02/18.
//

import SwiftUI

struct ContentView: View {
    @Bindable var viewModel: KanbanViewModel
    @Bindable var calendarViewModel: CalendarViewModel
    @State private var editViewModel: TaskEditViewModel?
    @State private var showSettings = false
    @State private var selectedTab: SidebarTab = .tasks

    init(viewModel: KanbanViewModel, calendarViewModel: CalendarViewModel) {
        self.viewModel = viewModel
        self.calendarViewModel = calendarViewModel
    }

    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()

            if viewModel.isLoading && viewModel.parentTasks.isEmpty && selectedTab == .tasks {
                ProgressView()
                    .progressViewStyle(.circular)
            } else {
                HStack(spacing: 0) {
                    // サイドバー
                    SidebarTabBar(selectedTab: $selectedTab)

                    Divider().background(Color.white.opacity(0.1))

                    // メインコンテンツ
                    switch selectedTab {
                    case .tasks:
                        tasksContent
                    case .calendar:
                        CalendarWeekView(viewModel: calendarViewModel)
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: editViewModel != nil)
            }
        }
        .sheet(isPresented: $showSettings) {
            CategorySettingsView(viewModel: viewModel)
                .frame(minWidth: 400, minHeight: 350)
        }
    }

    private var tasksContent: some View {
        HStack(spacing: 0) {
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
                            onCardTap: { task in
                                let vm = TaskEditViewModel(task: task, kanbanVM: viewModel)
                                editViewModel = vm
                                viewModel.isEditing = true
                            }
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }

            // 右側編集パネル
            if let editVM = editViewModel {
                Divider().background(Color.white.opacity(0.2))

                TaskEditView(
                    viewModel: editVM,
                    onDismiss: {
                        viewModel.isEditing = false
                        withAnimation(.easeInOut(duration: 0.25)) {
                            editViewModel = nil
                        }
                    }
                )
                .frame(width: 420)
                .transition(.move(edge: .trailing))
            }
        }
    }
}

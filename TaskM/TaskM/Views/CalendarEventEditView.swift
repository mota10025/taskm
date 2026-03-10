import EventKit
import SwiftUI

struct CalendarEventEditView: View {
    @Bindable var viewModel: CalendarViewModel
    @State private var title: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var isAllDay: Bool
    @State private var notes: String
    @State private var selectedCalendarId: String
    @State private var showDeleteConfirm = false
    @State private var errorMessage: String?

    private let event: EKEvent
    private let isNew: Bool

    init(viewModel: CalendarViewModel, event: EKEvent, isNew: Bool) {
        self.viewModel = viewModel
        self.event = event
        self.isNew = isNew
        self._title = State(initialValue: event.title ?? "")
        self._startDate = State(initialValue: event.startDate ?? Date())
        self._endDate = State(initialValue: event.endDate ?? Date().addingTimeInterval(3600))
        self._isAllDay = State(initialValue: event.isAllDay)
        self._notes = State(initialValue: event.notes ?? "")
        self._selectedCalendarId = State(initialValue: event.calendar?.calendarIdentifier ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            // ヘッダー
            header
            Divider().background(Color.white.opacity(0.1))

            // フォーム
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    titleField
                    calendarPicker
                    allDayToggle
                    dateTimePickers
                    notesField
                }
                .padding(16)
            }

            Divider().background(Color.white.opacity(0.1))

            // フッター
            footer
        }
        .background(AppColors.background)
        .alert("予定を削除", isPresented: $showDeleteConfirm) {
            Button("削除", role: .destructive) { performDelete() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("この予定を削除しますか？")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text(isNew ? "予定を作成" : "予定を編集")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
            Spacer()
            Button(action: { viewModel.dismissEdit() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.gray)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
    }

    // MARK: - Title

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("タイトル")
                .font(.system(size: 11))
                .foregroundColor(.gray)
            TextField("予定のタイトル", text: $title)
                .textFieldStyle(.plain)
                .padding(8)
                .background(Color.white.opacity(0.05))
                .cornerRadius(6)
                .foregroundColor(.white)
        }
    }

    // MARK: - Calendar Picker

    private var calendarPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("カレンダー")
                .font(.system(size: 11))
                .foregroundColor(.gray)
            Picker("", selection: $selectedCalendarId) {
                ForEach(viewModel.writableCalendars, id: \.calendarIdentifier) { cal in
                    HStack {
                        Circle()
                            .fill(Color(cgColor: cal.cgColor))
                            .frame(width: 8, height: 8)
                        Text(cal.title)
                    }
                    .tag(cal.calendarIdentifier)
                }
            }
            .pickerStyle(.menu)
            .tint(.white)
        }
    }

    // MARK: - All Day Toggle

    private var allDayToggle: some View {
        Toggle("終日", isOn: $isAllDay)
            .font(.system(size: 13))
            .foregroundColor(.white)
            .tint(Color(hex: 0x4285F4))
    }

    // MARK: - Date/Time Pickers

    private var dateTimePickers: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("開始")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
                DatePicker(
                    "",
                    selection: $startDate,
                    displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute]
                )
                .labelsHidden()
                .environment(\.locale, Locale(identifier: "ja_JP"))
                .onChange(of: startDate) { _, newValue in
                    if endDate <= newValue {
                        endDate = newValue.addingTimeInterval(3600)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("終了")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
                DatePicker(
                    "",
                    selection: $endDate,
                    in: startDate...,
                    displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute]
                )
                .labelsHidden()
                .environment(\.locale, Locale(identifier: "ja_JP"))
            }
        }
    }

    // MARK: - Notes

    private var notesField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("メモ")
                .font(.system(size: 11))
                .foregroundColor(.gray)
            TextEditor(text: $notes)
                .font(.system(size: 13))
                .foregroundColor(.white)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color.white.opacity(0.05))
                .cornerRadius(6)
                .frame(minHeight: 80)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if !isNew {
                Button(action: { showDeleteConfirm = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text("削除")
                    }
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: 0xf04438))
                }
                .buttonStyle(.plain)
            }

            Spacer()

            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: 0xf04438))
            }

            Button("キャンセル") {
                viewModel.dismissEdit()
            }
            .buttonStyle(.bordered)
            .tint(.gray)

            Button("保存") {
                performSave()
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(hex: 0x4285F4))
            .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(16)
    }

    // MARK: - Actions

    private func performSave() {
        event.title = title.trimmingCharacters(in: .whitespaces)
        event.startDate = startDate
        event.endDate = endDate
        event.isAllDay = isAllDay
        event.notes = notes.isEmpty ? nil : notes

        if let cal = viewModel.writableCalendars.first(where: { $0.calendarIdentifier == selectedCalendarId }) {
            event.calendar = cal
        }

        do {
            try viewModel.saveEvent(event)
        } catch {
            errorMessage = "保存に失敗しました: \(error.localizedDescription)"
        }
    }

    private func performDelete() {
        do {
            try viewModel.deleteEvent(event)
        } catch {
            errorMessage = "削除に失敗しました: \(error.localizedDescription)"
        }
    }
}

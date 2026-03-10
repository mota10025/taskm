import EventKit
import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class CalendarViewModel {
    var currentWeekStart: Date = CalendarViewModel.mondayOfWeek(for: Date())
    var events: [EKEvent] = []
    var googleCalendars: [EKCalendar] = []
    var authStatus: CalendarService.AuthStatus = .notDetermined
    var isLoading = false
    var errorMessage: String?

    private let calendarService = CalendarService.shared

    var weekDays: [Date] {
        (0..<7).compactMap { offset in
            Calendar.current.date(byAdding: .day, value: offset, to: currentWeekStart)
        }
    }

    func requestAccessAndLoad() {
        Task {
            let granted = await calendarService.requestAccess()
            authStatus = granted ? .authorized : .denied
            if granted {
                loadEvents()
            }
        }
    }

    func checkAuthAndLoad() {
        authStatus = calendarService.authStatus
        switch authStatus {
        case .authorized:
            loadEvents()
        case .notDetermined:
            requestAccessAndLoad()
        case .denied:
            break
        }
    }

    func loadEvents() {
        isLoading = true
        let startDate = currentWeekStart
        guard let endDate = Calendar.current.date(byAdding: .day, value: 7, to: startDate) else {
            isLoading = false
            return
        }
        googleCalendars = calendarService.googleCalendars()
        disabledCalendarIds = calendarService.disabledCalendarIds
        events = calendarService.events(from: startDate, to: endDate)
        isLoading = false
    }

    func goToPreviousWeek() {
        if let newStart = Calendar.current.date(byAdding: .day, value: -7, to: currentWeekStart) {
            currentWeekStart = newStart
            loadEvents()
        }
    }

    func goToNextWeek() {
        if let newStart = Calendar.current.date(byAdding: .day, value: 7, to: currentWeekStart) {
            currentWeekStart = newStart
            loadEvents()
        }
    }

    func goToToday() {
        currentWeekStart = CalendarViewModel.mondayOfWeek(for: Date())
        loadEvents()
    }

    func events(for date: Date) -> [EKEvent] {
        let calendar = Calendar.current
        return events.filter { event in
            guard !event.isAllDay else { return false }
            return calendar.isDate(event.startDate, inSameDayAs: date)
        }
    }

    func allDayEvents(for date: Date) -> [EKEvent] {
        let calendar = Calendar.current
        return events.filter { event in
            guard event.isAllDay else { return false }
            let start = calendar.startOfDay(for: event.startDate)
            let end = calendar.startOfDay(for: event.endDate)
            let day = calendar.startOfDay(for: date)
            return day >= start && day < end
        }
    }

    var hasAllDayEvents: Bool {
        events.contains { $0.isAllDay }
    }

    var showingSettings = false
    var disabledCalendarIds: Set<String> = []
    // 色の変更をトリガーするカウンター
    var colorVersion: Int = 0

    // MARK: - イベント編集

    var editingEvent: EKEvent?
    var isCreatingNewEvent = false

    /// 書き込み可能なカレンダー一覧
    var writableCalendars: [EKCalendar] {
        calendarService.writableCalendars()
    }

    func startEditingEvent(_ event: EKEvent) {
        editingEvent = event
        isCreatingNewEvent = false
    }

    func startCreatingEvent(at date: Date, hour: Int, minute: Int = 0) {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = hour
        components.minute = minute
        guard let startDate = calendar.date(from: components),
              let endDate = calendar.date(byAdding: .hour, value: 1, to: startDate) else { return }

        let event = EKEvent(eventStore: calendarService.eventStore)
        event.title = ""
        event.startDate = startDate
        event.endDate = endDate
        if let defaultCal = writableCalendars.first {
            event.calendar = defaultCal
        }
        editingEvent = event
        isCreatingNewEvent = true
    }

    func saveEvent(_ event: EKEvent) throws {
        if isCreatingNewEvent {
            _ = try calendarService.createEvent(
                title: event.title ?? "新しい予定",
                startDate: event.startDate,
                endDate: event.endDate,
                calendar: event.calendar,
                notes: event.notes,
                isAllDay: event.isAllDay
            )
        } else {
            try calendarService.updateEvent(event)
        }
        editingEvent = nil
        isCreatingNewEvent = false
        loadEvents()
    }

    func deleteEvent(_ event: EKEvent) throws {
        try calendarService.deleteEvent(event)
        editingEvent = nil
        loadEvents()
    }

    func moveEvent(_ event: EKEvent, to newStart: Date) throws {
        let duration = event.endDate.timeIntervalSince(event.startDate)
        event.startDate = newStart
        event.endDate = newStart.addingTimeInterval(duration)
        try calendarService.updateEvent(event)
        loadEvents()
    }

    func dismissEdit() {
        editingEvent = nil
        isCreatingNewEvent = false
    }

    func isCalendarEnabled(_ calendar: EKCalendar) -> Bool {
        !disabledCalendarIds.contains(calendar.calendarIdentifier)
    }

    func toggleCalendar(_ calendar: EKCalendar) {
        let id = calendar.calendarIdentifier
        if disabledCalendarIds.contains(id) {
            disabledCalendarIds.remove(id)
        } else {
            disabledCalendarIds.insert(id)
        }
        calendarService.setCalendarEnabled(calendar, enabled: !disabledCalendarIds.contains(id))
        loadEvents()
    }

    // MARK: - カレンダー色

    func bgColor(for event: EKEvent) -> Color {
        _ = colorVersion
        let calId = event.calendar.calendarIdentifier
        if let hex = calendarService.backgroundColor(for: calId, defaultColor: event.calendar.cgColor) {
            return Color(hex: UInt(hex))
        }
        return Color(cgColor: event.calendar.cgColor)
    }

    func textColor(for event: EKEvent) -> Color {
        _ = colorVersion
        let calId = event.calendar.calendarIdentifier
        if let hex = calendarService.textColor(for: calId) {
            return Color(hex: UInt(hex))
        }
        return .white
    }

    func calendarBgColor(for calendar: EKCalendar) -> Color {
        _ = colorVersion
        if let hex = calendarService.backgroundColor(for: calendar.calendarIdentifier, defaultColor: calendar.cgColor) {
            return Color(hex: UInt(hex))
        }
        return Color(cgColor: calendar.cgColor)
    }

    func setCalendarBgColor(_ calendar: EKCalendar, color: Color) {
        let hex = color.toHexInt()
        calendarService.setBackgroundColor(for: calendar.calendarIdentifier, hex: hex)
        colorVersion += 1
    }

    func setCalendarTextColor(_ calendar: EKCalendar, color: Color) {
        let hex = color.toHexInt()
        calendarService.setTextColor(for: calendar.calendarIdentifier, hex: hex)
        colorVersion += 1
    }

    func calendarTextColor(for calendar: EKCalendar) -> Color {
        _ = colorVersion
        if let hex = calendarService.textColor(for: calendar.calendarIdentifier) {
            return Color(hex: UInt(hex))
        }
        return .white
    }

    private static func mondayOfWeek(for date: Date) -> Date {
        var calendar = Calendar.current
        calendar.firstWeekday = 2 // Monday
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components) ?? date
    }
}

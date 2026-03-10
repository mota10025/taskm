import AppKit
import EventKit
import Foundation

@MainActor
final class CalendarService {
    static let shared = CalendarService()

    let eventStore = EKEventStore()
    private var store: EKEventStore { eventStore }

    enum AuthStatus {
        case notDetermined
        case authorized
        case denied
    }

    var authStatus: AuthStatus {
        let status = EKEventStore.authorizationStatus(for: .event)
        print("[CalendarService] EKAuthorizationStatus raw value: \(status.rawValue)")
        switch status {
        case .authorized, .fullAccess:
            return .authorized
        case .notDetermined:
            return .notDetermined
        default:
            return .denied
        }
    }

    func requestAccess() async -> Bool {
        print("[CalendarService] Requesting calendar access...")
        // NSPanelからの呼び出しではダイアログが表示されないため、
        // アプリを一時的にregularに切り替えてアクティブにする
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // 少し待ってからリクエスト（アクティベーションの反映を待つ）
        try? await Task.sleep(nanoseconds: 500_000_000)

        let requestStore = EKEventStore()
        if #available(macOS 14.0, *) {
            do {
                let result = try await requestStore.requestFullAccessToEvents()
                print("[CalendarService] requestFullAccessToEvents result: \(result)")
                NSApp.setActivationPolicy(.accessory)
                return result
            } catch {
                print("[CalendarService] requestFullAccessToEvents error: \(error)")
                NSApp.setActivationPolicy(.accessory)
                return false
            }
        } else {
            let result = await withCheckedContinuation { continuation in
                requestStore.requestAccess(to: .event) { granted, error in
                    print("[CalendarService] requestAccess result: \(granted), error: \(String(describing: error))")
                    continuation.resume(returning: granted)
                }
            }
            NSApp.setActivationPolicy(.accessory)
            return result
        }
    }

    func openCalendarSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Googleアカウントのカレンダーのみ返す（iCloud, Subscribed, Other を除外）
    func googleCalendars() -> [EKCalendar] {
        let allCalendars = store.calendars(for: .event)
        let filtered = allCalendars.filter { calendar in
            let source = calendar.source!
            guard source.sourceType == .calDAV else { return false }
            // iCloudを除外
            let title = source.title.lowercased()
            return title != "icloud"
        }
        return filtered
    }

    /// 有効なカレンダーのみ返す（ユーザーが選択したもの）
    func enabledCalendars() -> [EKCalendar] {
        let all = googleCalendars()
        let disabledIds = disabledCalendarIds
        if disabledIds.isEmpty { return all }
        return all.filter { !disabledIds.contains($0.calendarIdentifier) }
    }

    func events(from startDate: Date, to endDate: Date) -> [EKEvent] {
        let calendars = enabledCalendars()
        guard !calendars.isEmpty else { return [] }
        let predicate = store.predicateForEvents(
            withStart: startDate, end: endDate, calendars: calendars
        )
        return store.events(matching: predicate)
    }

    // MARK: - カレンダー表示設定（UserDefaults）

    private let disabledCalendarIdsKey = "TaskM_DisabledCalendarIds"

    var disabledCalendarIds: Set<String> {
        get {
            Set(UserDefaults.standard.stringArray(forKey: disabledCalendarIdsKey) ?? [])
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: disabledCalendarIdsKey)
        }
    }

    func isCalendarEnabled(_ calendar: EKCalendar) -> Bool {
        !disabledCalendarIds.contains(calendar.calendarIdentifier)
    }

    func setCalendarEnabled(_ calendar: EKCalendar, enabled: Bool) {
        var ids = disabledCalendarIds
        if enabled {
            ids.remove(calendar.calendarIdentifier)
        } else {
            ids.insert(calendar.calendarIdentifier)
        }
        disabledCalendarIds = ids
    }

    // MARK: - カレンダー色設定

    private let calendarColorsKey = "TaskM_CalendarColors"

    /// [calendarIdentifier: ["bg": hexInt, "text": hexInt]]
    private var storedColors: [String: [String: Int]] {
        get {
            UserDefaults.standard.dictionary(forKey: calendarColorsKey) as? [String: [String: Int]] ?? [:]
        }
        set {
            UserDefaults.standard.set(newValue, forKey: calendarColorsKey)
        }
    }

    func backgroundColor(for calendarId: String, defaultColor: CGColor) -> Int? {
        storedColors[calendarId]?["bg"]
    }

    func textColor(for calendarId: String) -> Int? {
        storedColors[calendarId]?["text"]
    }

    func setBackgroundColor(for calendarId: String, hex: Int) {
        var colors = storedColors
        var entry = colors[calendarId] ?? [:]
        entry["bg"] = hex
        colors[calendarId] = entry
        storedColors = colors
    }

    func setTextColor(for calendarId: String, hex: Int) {
        var colors = storedColors
        var entry = colors[calendarId] ?? [:]
        entry["text"] = hex
        colors[calendarId] = entry
        storedColors = colors
    }

    func resetColors(for calendarId: String) {
        var colors = storedColors
        colors.removeValue(forKey: calendarId)
        storedColors = colors
    }

    // MARK: - イベント作成・更新・削除

    func createEvent(
        title: String,
        startDate: Date,
        endDate: Date,
        calendar: EKCalendar,
        notes: String? = nil,
        isAllDay: Bool = false
    ) throws -> EKEvent {
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = startDate
        event.endDate = endDate
        event.calendar = calendar
        event.notes = notes
        event.isAllDay = isAllDay
        try store.save(event, span: .thisEvent)
        return event
    }

    func updateEvent(_ event: EKEvent, span: EKSpan = .thisEvent) throws {
        try store.save(event, span: span)
    }

    func deleteEvent(_ event: EKEvent, span: EKSpan = .thisEvent) throws {
        try store.remove(event, span: span)
    }

    /// EKEventStoreのイベントを直接取得（編集用）
    func event(withIdentifier identifier: String) -> EKEvent? {
        store.event(withIdentifier: identifier)
    }

    /// 書き込み可能なカレンダー一覧
    func writableCalendars() -> [EKCalendar] {
        googleCalendars().filter { $0.allowsContentModifications }
    }
}

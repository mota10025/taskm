import EventKit
import SwiftUI

struct CalendarWeekView: View {
    @Bindable var viewModel: CalendarViewModel
    private let hourHeight: CGFloat = 60
    private let timeGutterWidth: CGFloat = 50

    var body: some View {
        VStack(spacing: 0) {
            switch viewModel.authStatus {
            case .notDetermined:
                accessRequestView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .denied:
                deniedView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .authorized:
                if viewModel.googleCalendars.isEmpty && !viewModel.isLoading {
                    noCalendarsView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    calendarContent
                }
            }
        }
        .background(AppColors.background)
        .onAppear {
            viewModel.checkAuthAndLoad()
        }
    }

    // MARK: - State Views

    private var accessRequestView: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 48))
                .foregroundColor(Color(hex: 0x888888))
            Text("カレンダーへのアクセスが必要です")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
            Text("Googleカレンダーの予定を表示するには\nカレンダーへのアクセスを許可してください")
                .font(.system(size: 13))
                .foregroundColor(Color(hex: 0x888888))
                .multilineTextAlignment(.center)
            Button("アクセスを許可") {
                viewModel.requestAccessAndLoad()
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(hex: 0x4285F4))
        }
    }

    private var deniedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 48))
                .foregroundColor(Color(hex: 0x888888))
            Text("カレンダーへのアクセスが拒否されています")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
            Text("システム設定 → プライバシーとセキュリティ → カレンダー\nからTaskMへのアクセスを許可してください")
                .font(.system(size: 13))
                .foregroundColor(Color(hex: 0x888888))
                .multilineTextAlignment(.center)
        }
    }

    private var noCalendarsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar")
                .font(.system(size: 48))
                .foregroundColor(Color(hex: 0x888888))
            Text("Googleカレンダーが見つかりません")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
            Text("システム設定 → インターネットアカウント\nからGoogleアカウントを追加してください")
                .font(.system(size: 13))
                .foregroundColor(Color(hex: 0x888888))
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Calendar Content

    private var calendarContent: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                calendarHeader
                dayHeaders
                if viewModel.hasAllDayEvents {
                    allDayRow
                    Divider().background(AppColors.calendarGridLine)
                }
                timeGrid
            }

            // 編集パネル
            if viewModel.editingEvent != nil {
                Divider().background(Color.white.opacity(0.1))
                CalendarEventEditView(
                    viewModel: viewModel,
                    event: viewModel.editingEvent!,
                    isNew: viewModel.isCreatingNewEvent
                )
                .frame(width: 320)
            }
        }
    }

    // MARK: - Header

    private var calendarHeader: some View {
        HStack {
            Button(action: { viewModel.goToPreviousWeek() }) {
                Image(systemName: "chevron.left")
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)

            Button(action: { viewModel.goToNextWeek() }) {
                Image(systemName: "chevron.right")
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)

            Text(weekRangeText)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)

            Spacer()

            Button("今日") {
                viewModel.goToToday()
            }
            .buttonStyle(.bordered)
            .tint(.white)

            Button(action: { viewModel.showingSettings.toggle() }) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 16))
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $viewModel.showingSettings, arrowEdge: .bottom) {
                calendarSettingsPopover
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    // MARK: - Calendar Settings Popover

    private var calendarSettingsPopover: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("表示するカレンダー")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                let grouped = Dictionary(grouping: viewModel.googleCalendars) { $0.source.title }
                let sortedKeys = grouped.keys.sorted()

                ForEach(sortedKeys, id: \.self) { sourceTitle in
                    Text(sourceTitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                        .padding(.bottom, 4)

                    if let calendars = grouped[sourceTitle] {
                        ForEach(calendars, id: \.calendarIdentifier) { calendar in
                            CalendarSettingsRow(
                                calendar: calendar,
                                viewModel: viewModel
                            )
                        }
                    }
                }
            }
            .padding(.bottom, 12)
        }
        .frame(width: 300)
        .frame(maxHeight: 400)
    }

    // MARK: - Day Headers

    private var dayHeaders: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: timeGutterWidth, height: 1)

            ForEach(viewModel.weekDays, id: \.self) { date in
                dayHeaderCell(date: date)
                    .frame(maxWidth: .infinity)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.bottom, 2)
    }

    private func dayHeaderCell(date: Date) -> some View {
        let calendar = Calendar.current
        let isToday = calendar.isDateInToday(date)
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "ja_JP")
        dayFormatter.dateFormat = "E"
        let dayOfWeek = dayFormatter.string(from: date)
        let dayNumber = calendar.component(.day, from: date)

        return VStack(spacing: 0) {
            Text(dayOfWeek)
                .font(.system(size: 10))
                .foregroundColor(isToday ? Color(hex: 0x4285F4) : Color(hex: 0x888888))
            Text("\(dayNumber)")
                .font(.system(size: 14, weight: isToday ? .bold : .regular))
                .foregroundColor(isToday ? .white : Color(hex: 0xcccccc))
                .frame(width: 24, height: 24)
                .background(isToday ? Color(hex: 0x4285F4) : Color.clear)
                .clipShape(Circle())
        }
    }

    // MARK: - All Day Events

    private var allDayRow: some View {
        HStack(spacing: 0) {
            Text("終日")
                .font(.system(size: 10))
                .foregroundColor(Color(hex: 0x888888))
                .frame(width: timeGutterWidth)

            ForEach(viewModel.weekDays, id: \.self) { date in
                VStack(spacing: 2) {
                    ForEach(viewModel.allDayEvents(for: date), id: \.eventIdentifier) { event in
                        Text(event.title ?? "")
                            .font(.system(size: 10))
                            .foregroundColor(viewModel.textColor(for: event))
                            .lineLimit(1)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(viewModel.bgColor(for: event).opacity(0.85))
                            .cornerRadius(2)
                            .onTapGesture {
                                viewModel.startEditingEvent(event)
                            }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
    }

    // MARK: - Time Grid

    private var timeGrid: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                ZStack(alignment: .topLeading) {
                    // Scroll anchor markers (actual position, not offset)
                    VStack(spacing: 0) {
                        ForEach(0..<24, id: \.self) { hour in
                            Color.clear
                                .frame(height: hourHeight)
                                .id("hour\(hour)")
                        }
                    }

                    // Grid lines
                    gridLines

                    // Events
                    HStack(spacing: 0) {
                        Color.clear.frame(width: timeGutterWidth)

                        ForEach(viewModel.weekDays, id: \.self) { date in
                            dayColumn(for: date)
                                .frame(maxWidth: .infinity)
                        }
                    }

                    // Current time indicator
                    currentTimeIndicator
                }
                .frame(height: hourHeight * 24)
            }
            .onAppear {
                // Scroll to 1 hour before current time
                let scrollHour = max(Calendar.current.component(.hour, from: Date()) - 1, 0)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    proxy.scrollTo("hour\(scrollHour)", anchor: .top)
                }
            }
        }
    }

    private var gridLines: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<24, id: \.self) { hour in
                HStack(spacing: 0) {
                    // Time label
                    Text(hour == 0 ? "" : "\(hour):00")
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: 0x888888))
                        .frame(width: timeGutterWidth, alignment: .trailing)
                        .padding(.trailing, 4)

                    // Horizontal line
                    Rectangle()
                        .fill(AppColors.calendarGridLine)
                        .frame(height: 0.5)
                }
                .offset(y: CGFloat(hour) * hourHeight - 6)
            }

            // Vertical dividers between days
            HStack(spacing: 0) {
                Color.clear.frame(width: timeGutterWidth)

                ForEach(0..<7, id: \.self) { index in
                    if index > 0 {
                        Rectangle()
                            .fill(AppColors.calendarGridLine)
                            .frame(width: 0.5)
                    }
                    Color.clear.frame(maxWidth: .infinity)
                }
            }
            .frame(height: hourHeight * 24)
        }
    }

    private func dayColumn(for date: Date) -> some View {
        let dayEvents = viewModel.events(for: date)
        let layoutItems = computeOverlapGroups(dayEvents)

        return GeometryReader { geometry in
            let columnWidth = geometry.size.width
            ZStack(alignment: .topLeading) {
                // クリックで新規作成（背景タップ領域）
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        let totalMinutes = location.y / hourHeight * 60
                        let hour = Int(totalMinutes / 60)
                        let minute = Int(totalMinutes.truncatingRemainder(dividingBy: 60) / 15) * 15
                        viewModel.startCreatingEvent(at: date, hour: hour, minute: minute)
                    }

                ForEach(layoutItems, id: \.event.eventIdentifier) { item in
                    let itemWidth = columnWidth / CGFloat(item.totalColumns)
                    let xOffset = CGFloat(item.columnIndex) * itemWidth
                    CalendarEventBlock(
                        event: item.event,
                        hourHeight: hourHeight,
                        bgColor: viewModel.bgColor(for: item.event),
                        textColor: viewModel.textColor(for: item.event),
                        onTap: {
                            viewModel.startEditingEvent(item.event)
                        },
                        onDragEnd: { dragPixels in
                            let minutesMoved = dragPixels / hourHeight * 60
                            let newStart = item.event.startDate.addingTimeInterval(Double(minutesMoved) * 60)
                            try? viewModel.moveEvent(item.event, to: newStart)
                        }
                    )
                    .frame(width: itemWidth - 2)
                    .offset(x: xOffset + 1)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: hourHeight * 24)
    }

    // MARK: - Current Time Indicator

    private var currentTimeIndicator: some View {
        let calendar = Calendar.current
        let now = Date()
        let hour = CGFloat(calendar.component(.hour, from: now))
        let minute = CGFloat(calendar.component(.minute, from: now))
        let yPos = (hour * 60 + minute) * (hourHeight / 60)

        // Check if today is in the current week
        let isInWeek = viewModel.weekDays.contains { calendar.isDateInToday($0) }

        return Group {
            if isInWeek {
                HStack(spacing: 0) {
                    // Time gutter with current time label
                    Text(String(format: "%d:%02d", Int(hour), Int(minute)))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(AppColors.calendarCurrentTimeLine)
                        .frame(width: timeGutterWidth, alignment: .trailing)
                        .padding(.trailing, 4)

                    // Red dot + line
                    Circle()
                        .fill(AppColors.calendarCurrentTimeLine)
                        .frame(width: 8, height: 8)
                        .offset(x: -4)

                    Rectangle()
                        .fill(AppColors.calendarCurrentTimeLine)
                        .frame(height: 2)
                        .offset(x: -4)
                }
                .offset(y: yPos - 4)
            }
        }
    }

    // MARK: - Helpers

    private var weekRangeText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")

        guard let lastDay = viewModel.weekDays.last else { return "" }
        let firstDay = viewModel.weekDays[0]

        let yearFormatter = DateFormatter()
        yearFormatter.dateFormat = "yyyy年"

        formatter.dateFormat = "M月d日"
        let start = formatter.string(from: firstDay)
        let end = formatter.string(from: lastDay)
        let year = yearFormatter.string(from: firstDay)

        return "\(year) \(start) - \(end)"
    }

    // MARK: - Overlap Calculation

    private struct EventLayoutItem {
        let event: EKEvent
        let columnIndex: Int
        let totalColumns: Int
    }

    private func computeOverlapGroups(_ events: [EKEvent]) -> [EventLayoutItem] {
        guard !events.isEmpty else { return [] }

        let sorted = events.sorted { $0.startDate < $1.startDate }
        var result: [EventLayoutItem] = []
        var groups: [[EKEvent]] = []

        for event in sorted {
            var placed = false
            for i in groups.indices {
                let groupEnd = groups[i].map { $0.endDate ?? Date.distantPast }.max() ?? Date.distantPast
                if event.startDate >= groupEnd {
                    groups[i].append(event)
                    placed = true
                    break
                }
            }
            if !placed {
                groups.append([event])
            }
        }

        // Simple approach: find overlapping clusters
        var clusters: [[(event: EKEvent, column: Int)]] = []
        var currentCluster: [(event: EKEvent, column: Int)] = []
        var clusterEnd: Date = .distantPast

        for event in sorted {
            if event.startDate >= clusterEnd {
                if !currentCluster.isEmpty {
                    clusters.append(currentCluster)
                }
                currentCluster = [(event, 0)]
                clusterEnd = event.endDate
            } else {
                let column = currentCluster.count
                currentCluster.append((event, column))
                if event.endDate > clusterEnd {
                    clusterEnd = event.endDate
                }
            }
        }
        if !currentCluster.isEmpty {
            clusters.append(currentCluster)
        }

        for cluster in clusters {
            let totalCols = cluster.count
            for item in cluster {
                result.append(EventLayoutItem(
                    event: item.event,
                    columnIndex: item.column,
                    totalColumns: totalCols
                ))
            }
        }

        return result
    }
}

// MARK: - Calendar Settings Row

private struct CalendarSettingsRow: View {
    let calendar: EKCalendar
    @Bindable var viewModel: CalendarViewModel
    @State private var bgColor: Color
    @State private var txtColor: Color

    init(calendar: EKCalendar, viewModel: CalendarViewModel) {
        self.calendar = calendar
        self.viewModel = viewModel
        self._bgColor = State(initialValue: viewModel.calendarBgColor(for: calendar))
        self._txtColor = State(initialValue: viewModel.calendarTextColor(for: calendar))
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: { viewModel.toggleCalendar(calendar) }) {
                Image(systemName: viewModel.isCalendarEnabled(calendar) ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14))
                    .foregroundColor(viewModel.isCalendarEnabled(calendar) ? .blue : .secondary)
            }
            .buttonStyle(.plain)

            Text(calendar.title)
                .font(.system(size: 12))
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer()

            ColorPicker("", selection: $bgColor, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 20, height: 20)
                .onChange(of: bgColor) { _, newValue in
                    viewModel.setCalendarBgColor(calendar, color: newValue)
                }

            ColorPicker("", selection: $txtColor, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 20, height: 20)
                .overlay(
                    Text("A")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(txtColor)
                        .allowsHitTesting(false)
                )
                .onChange(of: txtColor) { _, newValue in
                    viewModel.setCalendarTextColor(calendar, color: newValue)
                }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
    }
}

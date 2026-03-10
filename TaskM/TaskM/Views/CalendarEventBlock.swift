import EventKit
import SwiftUI

struct CalendarEventBlock: View {
    let event: EKEvent
    let hourHeight: CGFloat
    let bgColor: Color
    let textColor: Color
    var onTap: (() -> Void)?
    var onDragMove: ((CGFloat) -> Void)?
    var onDragEnd: ((CGFloat) -> Void)?

    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false

    private var startMinutes: CGFloat {
        let calendar = Calendar.current
        let hour = CGFloat(calendar.component(.hour, from: event.startDate))
        let minute = CGFloat(calendar.component(.minute, from: event.startDate))
        return hour * 60 + minute
    }

    private var durationMinutes: CGFloat {
        let duration = event.endDate.timeIntervalSince(event.startDate) / 60
        return max(CGFloat(duration), 20)
    }

    private var yOffset: CGFloat {
        startMinutes * (hourHeight / 60)
    }

    private var height: CGFloat {
        durationMinutes * (hourHeight / 60)
    }

    private var canEdit: Bool {
        event.calendar?.allowsContentModifications ?? false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(event.title ?? "")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(textColor)
                .lineLimit(2)

            if durationMinutes >= 40 {
                Text(timeRangeText)
                    .font(.system(size: 10))
                    .foregroundColor(textColor.opacity(0.7))
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: height, alignment: .top)
        .background(bgColor.opacity(isDragging ? 0.6 : 0.85))
        .cornerRadius(4)
        .clipped()
        .offset(y: yOffset + dragOffset)
        .onTapGesture {
            onTap?()
        }
        .gesture(
            canEdit ? dragGesture : nil
        )
        .cursor(canEdit ? .openHand : .arrow)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                isDragging = true
                // 15分単位にスナップ
                let snapInterval = hourHeight / 4
                dragOffset = round(value.translation.height / snapInterval) * snapInterval
            }
            .onEnded { value in
                isDragging = false
                let snapInterval = hourHeight / 4
                let snapped = round(value.translation.height / snapInterval) * snapInterval
                if snapped != 0 {
                    onDragEnd?(snapped)
                }
                dragOffset = 0
            }
    }

    private var timeRangeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "H:mm"
        return "\(formatter.string(from: event.startDate)) - \(formatter.string(from: event.endDate))"
    }
}

// MARK: - Cursor Helper

private extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        onHover { inside in
            if inside {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

import SwiftUI

enum SidebarTab {
    case tasks
    case calendar
}

struct SidebarTabBar: View {
    @Binding var selectedTab: SidebarTab

    var body: some View {
        VStack(spacing: 4) {
            SidebarTabButton(
                icon: "checklist",
                isSelected: selectedTab == .tasks,
                action: { selectedTab = .tasks }
            )
            SidebarTabButton(
                icon: "calendar",
                isSelected: selectedTab == .calendar,
                action: { selectedTab = .calendar }
            )
            Spacer()
        }
        .padding(.vertical, 12)
        .frame(width: 48)
        .background(AppColors.sidebarBackground)
    }
}

private struct SidebarTabButton: View {
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(isSelected ? .white : Color(hex: 0x888888))
                .frame(width: 36, height: 36)
                .background(isSelected ? Color.white.opacity(0.1) : Color.clear)
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

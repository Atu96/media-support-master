import SwiftUI

enum WorkspaceSlideRailEdge {
    case leading
    case trailing

    var collapseIcon: String {
        switch self {
        case .leading: "chevron.left"
        case .trailing: "chevron.right"
        }
    }
}

/// Nút icon trên viền workspace — không nhãn dọc, cùng ngôn ngữ với sidebar.
struct WorkspaceChromeIconButton: View {
    var systemImage: String? = nil
    var brandMark: Bool = false
    var isActive: Bool = false
    var isEnabled: Bool = true
    var helpText: String = ""
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button {
            guard isEnabled else { return }
            action()
        } label: {
            Group {
                if brandMark {
                    AppMark(size: 26)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: isActive ? .semibold : .medium))
                        .foregroundStyle(
                            isEnabled
                                ? (isActive ? Color.white : Color.white.opacity(0.62))
                                : Color.white.opacity(0.32)
                        )
                }
            }
            .frame(width: 32, height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(pillFill)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(isActive ? 0.88 : 0.42), lineWidth: 0.75)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(AppPlainButtonStyle())
        .disabled(!isEnabled)
        .onHover { isHovered = $0 }
        .help(L10n.string(helpText))
    }

    private var pillFill: Color {
        if isActive { return Color.white.opacity(0.24) }
        if isHovered && isEnabled { return Color.white.opacity(0.16) }
        return Color.white.opacity(0.08)
    }
}

/// Cột icon viền phải — toggle panel phụ (Kiểu sub…).
struct WorkspaceSlideRail: View {
    let isOpen: Bool
    let icon: String
    var helpText: String = ""
    var isEnabled: Bool = true
    var edge: WorkspaceSlideRailEdge = .trailing
    var width: CGFloat = 44
    let action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceChromeIconButton(
                systemImage: isOpen ? edge.collapseIcon : icon,
                isActive: isOpen,
                isEnabled: isEnabled,
                helpText: helpText,
                action: action
            )
            .padding(.top, 12)

            Spacer(minLength: 0)
        }
        .frame(width: width)
        .frame(maxHeight: .infinity)
    }
}

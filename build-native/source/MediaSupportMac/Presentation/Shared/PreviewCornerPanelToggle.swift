import SwiftUI

/// Nút thu/mở panel — nằm góc trong khung preview, không chiếm viền workspace.
struct PreviewCornerPanelToggle: View {
    let isOpen: Bool
    let icon: String
    var isEnabled: Bool = true
    var helpText: String = "Kiểu sub"
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button {
            guard isEnabled else { return }
            action()
        } label: {
            Image(systemName: isOpen ? "chevron.right" : icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(Color.black.opacity(isHovered ? 0.58 : 0.46))
                )
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(isOpen ? 0.55 : 0.28), lineWidth: 0.75)
                }
                .shadow(color: .black.opacity(0.22), radius: 4, y: 2)
        }
        .buttonStyle(AppPlainButtonStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.42)
        .onHover { isHovered = $0 }
        .help(isOpen ? "Đóng \(helpText)" : helpText)
    }
}
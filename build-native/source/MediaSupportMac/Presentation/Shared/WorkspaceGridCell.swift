import SwiftUI

extension View {
    /// Ô lưới workspace cố định chiều cao (Tạo sub / Chỉnh sửa sub).
    func workspaceGridCell(height: CGFloat, width: CGFloat? = nil) -> some View {
        Group {
            if let width {
                frame(width: width, height: height, alignment: .top)
            } else {
                frame(maxWidth: .infinity)
                    .frame(height: height, alignment: .top)
            }
        }
    }
}
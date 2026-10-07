import SwiftUI

/// Bấm để đổi giữa bản gốc và bản dịch (review Tạo sub + chỉnh sửa).
struct SubtitleVariantSwitcher: View {
    let label: String
    let hint: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .center, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 10, weight: .semibold))
                    Text(L10n.string(label))
                        .font(AppFont.caption)
                        .fontWeight(.medium)
                }
                .foregroundStyle(AppTheme.accentBlue)

                if !hint.isEmpty {
                    Text(L10n.string(hint))
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.mutedText)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .buttonStyle(AppPlainButtonStyle())
        .help(hint.isEmpty ? L10n.string(label) : "\(L10n.string(label)) — \(L10n.string(hint))")
    }
}

/// Popover hướng dẫn chỉnh sub.
struct SubtitleEditGuideButton: View {
    @State private var isPresented = false

    var body: some View {
        AppPillButton(
            title: "Hướng dẫn",
            icon: "questionmark.circle",
            tint: AppTheme.accentBlue,
            filled: false
        ) {
            isPresented.toggle()
        }
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            SubtitleEditGuideContent(onClose: { isPresented = false })
        }
    }
}

struct SubtitleEditGuideContent: View {
    var onClose: () -> Void = {}

    private let panelWidth: CGFloat = 460
    private let panelMaxHeight: CGFloat = 540
    private let keyColumnWidth: CGFloat = 132

    var body: some View {
        VStack(spacing: 0) {
            guideHeader

            Rectangle()
                .fill(AppTheme.divider)
                .frame(height: 1)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    guideTable(
                        title: "Xem & sửa",
                        rows: [
                            ("Click dòng", "Tua tới đoạn (~2s vào cue), không tự phát"),
                            ("Double-click", "Sửa text trực tiếp trong dòng"),
                            ("Enter", "Xuống dòng trong text (lưu sẽ auto-ngắt theo chữ/dòng)"),
                            ("Rời dòng", "Click chỗ khác — tự lưu thay đổi"),
                            ("Esc", "Hủy sửa, không lưu"),
                        ]
                    )

                    guideTable(
                        title: "Phím & chuột",
                        rows: [
                            ("↑ / ↓", "Chọn dòng kế, tua theo dòng"),
                            ("Shift + click", "Chọn nhiều dòng liền kề để Gộp"),
                            ("Chuột phải", "Gộp timecode"),
                            ("⌘Z / ⌘⇧Z", "Hoàn tác / Làm lại"),
                        ]
                    )

                    guideTable(
                        title: "Gốc & dịch",
                        rows: [
                            ("Đang xem…", "Bấm nhãn bên trái thanh transcript để đổi gốc ↔ dịch"),
                            ("Dự án", "Menu «Dự án» trên preview — đổi video khi có nhiều SRT"),
                            ("Dịch", "Tab tạo sub — chọn ngôn ngữ từ menu; engine trong Cài đặt"),
                        ]
                    )

                    guideTable(
                        title: "Xuất file",
                        rows: [
                            ("Sao chép", "Copy toàn bộ transcript đang xem"),
                            ("TXT / SRT", "Xuất ra thư mục dự án bên cạnh video"),
                        ]
                    )
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: panelMaxHeight - 72)
        }
        .frame(width: panelWidth)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppTheme.tileStroke, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.14), radius: 18, y: 8)
    }

    private var guideHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppTheme.accentBlue.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: "text.badge.checkmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppTheme.accentBlue)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Hướng dẫn chỉnh sub")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.headlineText)
                Text("Phím tắt và thao tác trên khung transcript")
                    .font(AppFont.caption)
                    .foregroundStyle(AppTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppTheme.mutedText)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(AppTheme.divider.opacity(0.35))
                    )
            }
            .buttonStyle(AppPlainButtonStyle())
            .help("Đóng")
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private func guideTable(title: String, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            AppSectionHeader(title: title)

            VStack(spacing: 0) {
                guideTableHeader

                tableRule

                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    guideTableRow(key: row.0, detail: row.1, shaded: index.isMultiple(of: 2))

                    if index < rows.count - 1 {
                        tableRule
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(AppTheme.divider, lineWidth: 1)
            )
        }
    }

    private var guideTableHeader: some View {
        HStack(alignment: .center, spacing: 0) {
            Text("Thao tác")
                .frame(width: keyColumnWidth, alignment: .leading)
                .padding(.leading, 12)
            tableColumnRule
            Text("Mô tả")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 12)
                .padding(.trailing, 12)
        }
        .font(AppFont.label)
        .foregroundStyle(AppTheme.mutedText)
        .padding(.vertical, 9)
        .background(AppTheme.accentBlue.opacity(0.08))
    }

    private func guideTableRow(key: String, detail: String, shaded: Bool) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(key)
                .font(AppFont.mono)
                .foregroundStyle(AppTheme.accentBlue)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .frame(width: keyColumnWidth, alignment: .leading)
                .padding(.leading, 12)
                .padding(.vertical, 10)

            tableColumnRule

            Text(L10n.string(detail))
                .font(AppFont.body)
                .foregroundStyle(AppTheme.bodyText)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
        .background(shaded ? AppTheme.divider.opacity(0.22) : Color.clear)
    }

    private var tableRule: some View {
        Divider()
    }

    private var tableColumnRule: some View {
        Divider()
            .frame(width: 1)
    }
}

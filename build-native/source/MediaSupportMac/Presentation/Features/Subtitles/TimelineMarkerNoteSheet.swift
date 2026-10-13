import SwiftUI

struct TimelineMarkerNoteSheet: View {
    let marker: TimelineMarker
    let save: (String) -> Bool
    let delete: () -> Bool
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    @State private var note = ""
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Ghi chú đánh dấu", systemImage: "flag.fill")
                .font(AppFont.sectionTitle)
                .foregroundStyle(AppTheme.headlineText)
            Text(SRTTimecode.format(marker.seconds))
                .font(AppFont.editorTimecode).foregroundStyle(AppTheme.mutedText)
            Text("Ghi lại việc cần làm ở vị trí này, ví dụ: dịch lại, rà phụ đề hoặc kiểm tra giọng.")
                .font(AppFont.caption).foregroundStyle(AppTheme.mutedText)
            TextEditor(text: $note)
                .font(AppFont.label).focused($focused)
                .scrollContentBackground(.hidden)
                .padding(8).frame(height: 150)
                .background(AppFieldSurface(radius: AppTheme.editorControlRadius))
                .accessibilityLabel("Ghi chú đánh dấu")
            if failed {
                Text("Không lưu được ghi chú. Hãy kiểm tra quyền ghi thư mục dự án.")
                    .font(AppFont.caption).foregroundStyle(AppTheme.accentOrange)
            }
            HStack {
                Button("Xóa đánh dấu", role: .destructive) { if delete() { dismiss() } else { failed = true } }
                Spacer()
                Button("Hủy") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Lưu ghi chú") { if save(note) { dismiss() } else { failed = true } }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(22).frame(width: 440)
        .background(AppTheme.tileFill)
        .onAppear { note = marker.note; focused = true }
    }
}
